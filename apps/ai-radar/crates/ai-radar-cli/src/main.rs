//! AI Radar — CLI entrypoint (`collect`, `extract`, …).
//!
//! See `docs/AI-RADAR-DECISIONS.md` for the full command matrix; **T-161**
//! implements `collect` for RSS/Atom sources.

#![forbid(unsafe_code)]
#![warn(clippy::pedantic)]

use ai_radar_core::config::AppConfig;
use ai_radar_core::db::Database;
use ai_radar_core::domain::SourceType;
use ai_radar_core::llm::{build_llm_provider, CompletionRequest};
use ai_radar_core::pipeline::collect::run_collect;
use ai_radar_core::pipeline::compare::run_compare;
use ai_radar_core::pipeline::digest::{run_digest, DigestKind, DigestLimits};
use ai_radar_core::pipeline::extract::run_extract;
use ai_radar_core::pipeline::reprocess::{run_reprocess, ReprocessStage};
use ai_radar_core::pipeline::score::{run_score, DEFAULT_SCORE_STALE_HOURS};
use ai_radar_core::telemetry;
use anyhow::Context;
use clap::{ArgAction, Parser, Subcommand};
use tracing::Instrument;
use uuid::Uuid;

#[derive(Debug, Parser)]
#[command(
    name = "ai-radar",
    version = ai_radar_core::VERSION,
    about = "AI Radar — Decision Engine for AI tooling curation",
    long_about = None,
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// One-shot chat completion against the configured LLM (smoke / ops).
    LlmPing {
        /// User message sent to the model.
        #[arg(
            long,
            default_value = "Reply with only the lowercase word ok and nothing else."
        )]
        prompt: String,
    },
    /// Score `extracted_items` with deterministic rules (`deterministic-v1`).
    Score {
        /// Max rows to process.
        #[arg(long, default_value_t = 50)]
        limit: i64,
        /// Hours since last score of the same version before re-eligibility.
        #[arg(long, default_value_t = DEFAULT_SCORE_STALE_HOURS)]
        stale_hours: i64,
        /// Ignore recency and rescore the oldest rows up to `--limit`.
        #[arg(long, action = ArgAction::SetTrue)]
        rescore_all: bool,
    },
    /// Turn `pending` `raw_items` into `extracted_items` via LLM (sequential).
    Extract {
        /// Max rows to claim per run.
        #[arg(long, default_value_t = 50)]
        limit: i64,
    },
    /// Fetch RSS/Atom feeds and insert idempotent `raw_items` rows.
    Collect {
        /// Process only this source id (must be enabled and match `--source-type`).
        #[arg(long)]
        source_id: Option<Uuid>,
        /// Filter sources: `rss`, `github_releases`, `github_repo`, `webpage`.
        #[arg(long, default_value = "rss")]
        source_type: String,
    },
    /// Re-run extract and/or score for one extracted item (new version on extract).
    Reprocess {
        /// `extracted_items.id` to anchor the raw item.
        #[arg(long)]
        item: Uuid,
        /// `extract`, `score`, or `all`.
        #[arg(long, default_value = "all")]
        stage: String,
    },
    /// Compare tools within one category and print Markdown (**T-168**).
    Compare {
        /// Category label (must match `extracted_items.category`).
        #[arg(long)]
        category: String,
        /// Number of top-scored tools to include.
        #[arg(long, default_value_t = 5)]
        top: usize,
    },
    /// Generate a Markdown digest and persist it in `ai_radar.digests`.
    Digest {
        /// Generate a daily digest (last 24h).
        #[arg(long, action = ArgAction::SetTrue)]
        daily: bool,
        /// Generate a weekly digest (last 7 days).
        #[arg(long, action = ArgAction::SetTrue)]
        weekly: bool,
    },
}

async fn run_collect_command(
    job_id: Uuid,
    source_id: Option<Uuid>,
    source_type: String,
) -> anyhow::Result<()> {
    let started = std::time::Instant::now();
    let config = AppConfig::from_env().context("configuration")?;
    telemetry::init_tracing(&config.log_level).context("tracing")?;

    tracing::info!(
        event = "job.started",
        job = "collect",
        job_id = %job_id,
        "collect job started"
    );

    let database_url = config
        .database_url
        .clone()
        .ok_or_else(|| anyhow::anyhow!("DATABASE_URL is required for collect"))?;

    let filter = SourceType::parse(source_type.trim())
        .map_err(|e| anyhow::anyhow!("invalid --source-type {source_type:?}: {e}"))?;

    let db = Database::connect(&database_url)
        .await
        .map_err(|e| anyhow::anyhow!("database: {e}"))?;

    let stats = run_collect(&db, &config, filter, source_id)
        .await
        .context("collect pipeline")?;

    tracing::info!(
        event = "job.completed",
        job = "collect",
        job_id = %job_id,
        collected = stats.collected,
        skipped = stats.skipped,
        source_errors = stats.source_errors,
        total_sources = stats.total_sources,
        skipped_poll = stats.skipped_poll,
        duration_secs = started.elapsed().as_secs_f64(),
        "collect job finished"
    );

    println!(
        "collected={} skipped={} errors={} ({} sources, {} skipped poll)",
        stats.collected,
        stats.skipped,
        stats.source_errors,
        stats.total_sources,
        stats.skipped_poll
    );

    if stats.total_sources > 0 && stats.source_errors == stats.total_sources {
        std::process::exit(1);
    }

    Ok(())
}

async fn run_score_command(
    job_id: Uuid,
    limit: i64,
    stale_hours: i64,
    rescore_all: bool,
) -> anyhow::Result<()> {
    let started = std::time::Instant::now();
    let config = AppConfig::from_env().context("configuration")?;
    telemetry::init_tracing(&config.log_level).context("tracing")?;

    tracing::info!(
        event = "job.started",
        job = "score",
        job_id = %job_id,
        limit,
        stale_hours,
        rescore_all,
        "score job started"
    );

    let database_url = config
        .database_url
        .clone()
        .ok_or_else(|| anyhow::anyhow!("DATABASE_URL is required for score"))?;

    let db = Database::connect(&database_url)
        .await
        .map_err(|e| anyhow::anyhow!("database: {e}"))?;

    let stats = run_score(&db, &config, limit.max(1), stale_hours.max(1), rescore_all)
        .await
        .context("score pipeline")?;

    tracing::info!(
        event = "job.completed",
        job = "score",
        job_id = %job_id,
        scored = stats.scored,
        failed = stats.failed,
        duration_secs = started.elapsed().as_secs_f64(),
        "score job finished"
    );

    println!("scored={} failed={}", stats.scored, stats.failed);

    Ok(())
}

async fn run_extract_command(job_id: Uuid, limit: i64) -> anyhow::Result<()> {
    let started = std::time::Instant::now();
    let config = AppConfig::from_env().context("configuration")?;
    telemetry::init_tracing(&config.log_level).context("tracing")?;

    tracing::info!(
        event = "job.started",
        job = "extract",
        job_id = %job_id,
        limit,
        "extract job started"
    );

    let database_url = config
        .database_url
        .clone()
        .ok_or_else(|| anyhow::anyhow!("DATABASE_URL is required for extract"))?;

    let db = Database::connect(&database_url)
        .await
        .map_err(|e| anyhow::anyhow!("database: {e}"))?;

    let llm = build_llm_provider(&config);
    let stats = run_extract(&db, &config, llm, limit.max(1))
        .await
        .context("extract pipeline")?;

    tracing::info!(
        event = "job.completed",
        job = "extract",
        job_id = %job_id,
        extracted = stats.extracted,
        failed = stats.failed,
        duration_secs = started.elapsed().as_secs_f64(),
        "extract job finished"
    );

    println!("extracted={} failed={}", stats.extracted, stats.failed);

    Ok(())
}

async fn run_compare_command(category: String, top: usize) -> anyhow::Result<()> {
    let config = AppConfig::from_env().context("configuration")?;
    telemetry::init_tracing(&config.log_level).context("tracing")?;

    let database_url = config
        .database_url
        .clone()
        .ok_or_else(|| anyhow::anyhow!("DATABASE_URL is required for compare"))?;

    let db = Database::connect(&database_url)
        .await
        .map_err(|e| anyhow::anyhow!("database: {e}"))?;

    let result = run_compare(&db, &category, top)
        .await
        .context("compare pipeline")?;

    println!("comparison_id={}", result.comparison.id);
    println!("{}", result.markdown);
    Ok(())
}

async fn run_digest_command(job_id: Uuid, kind: DigestKind) -> anyhow::Result<()> {
    let started = std::time::Instant::now();
    let config = AppConfig::from_env().context("configuration")?;
    telemetry::init_tracing(&config.log_level).context("tracing")?;

    tracing::info!(
        event = "job.started",
        job = "digest",
        job_id = %job_id,
        kind = %kind.as_digest_type().as_str(),
        "digest job started"
    );

    let database_url = config
        .database_url
        .clone()
        .ok_or_else(|| anyhow::anyhow!("DATABASE_URL is required for digest"))?;

    let db = Database::connect(&database_url)
        .await
        .map_err(|e| anyhow::anyhow!("database: {e}"))?;

    let digest_id = run_digest(&db, kind, DigestLimits::default())
        .await
        .context("digest pipeline")?;

    tracing::info!(
        event = "job.completed",
        job = "digest",
        job_id = %job_id,
        digest_id = %digest_id,
        duration_secs = started.elapsed().as_secs_f64(),
        "digest job finished"
    );

    println!("digest_id={digest_id}");
    Ok(())
}

async fn run_reprocess_command(item: Uuid, stage: String) -> anyhow::Result<()> {
    let config = AppConfig::from_env().context("configuration")?;
    telemetry::init_tracing(&config.log_level).context("tracing")?;

    let database_url = config
        .database_url
        .clone()
        .ok_or_else(|| anyhow::anyhow!("DATABASE_URL is required for reprocess"))?;

    let db = Database::connect(&database_url)
        .await
        .map_err(|e| anyhow::anyhow!("database: {e}"))?;

    let stage = ReprocessStage::parse(&stage)?;
    let llm = build_llm_provider(&config);
    let out = run_reprocess(&db, &config, llm, item, stage).await?;

    println!(
        "raw_item_id={} latest_extracted_item_id={:?} latest_version={:?} scored={}",
        out.raw_item_id, out.latest_extracted_item_id, out.latest_version, out.scored
    );
    Ok(())
}

async fn run_llm_ping(prompt: String) -> anyhow::Result<()> {
    let config = AppConfig::from_env().context("configuration")?;
    telemetry::init_tracing(&config.log_level).context("tracing")?;

    let provider = build_llm_provider(&config);
    let req = CompletionRequest {
        system: "You are a concise assistant.".into(),
        user: prompt,
        max_tokens: 64,
        temperature: 0.0,
        json_mode: false,
    };

    match provider.complete(req).await {
        Ok(resp) => {
            println!("{}", resp.content.trim());
            Ok(())
        }
        Err(e) => {
            anyhow::bail!("llm: {e}")
        }
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    if cfg!(debug_assertions) {
        let _ = dotenvy::dotenv();
    }

    let cli = Cli::parse();

    match cli.command {
        Command::LlmPing { prompt } => {
            run_llm_ping(prompt).await?;
        }
        Command::Score {
            limit,
            stale_hours,
            rescore_all,
        } => {
            let job_id = Uuid::new_v4();
            let span = tracing::info_span!("score_job", job_id = %job_id);
            run_score_command(job_id, limit, stale_hours, rescore_all)
                .instrument(span)
                .await?;
        }
        Command::Extract { limit } => {
            let job_id = Uuid::new_v4();
            let span = tracing::info_span!("extract_job", job_id = %job_id);
            run_extract_command(job_id, limit).instrument(span).await?;
        }
        Command::Collect {
            source_id,
            source_type,
        } => {
            let job_id = Uuid::new_v4();
            let span = tracing::info_span!("collect_job", job_id = %job_id);
            run_collect_command(job_id, source_id, source_type)
                .instrument(span)
                .await?;
        }
        Command::Reprocess { item, stage } => {
            run_reprocess_command(item, stage).await?;
        }
        Command::Compare { category, top } => {
            run_compare_command(category, top).await?;
        }
        Command::Digest { daily, weekly } => {
            let kind = match (daily, weekly) {
                (true, false) => DigestKind::Daily,
                (false, true) => DigestKind::Weekly,
                _ => anyhow::bail!("exactly one of --daily or --weekly must be set"),
            };
            let job_id = Uuid::new_v4();
            let span = tracing::info_span!("digest_job", job_id = %job_id);
            run_digest_command(job_id, kind).instrument(span).await?;
        }
    }

    Ok(())
}
