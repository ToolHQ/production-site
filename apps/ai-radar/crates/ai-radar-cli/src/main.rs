//! AI Radar — CLI entrypoint (`collect`, `extract`, …).
//!
//! See `docs/AI-RADAR-DECISIONS.md` for the full command matrix; **T-161**
//! implements `collect` for RSS/Atom sources.

#![forbid(unsafe_code)]
#![warn(clippy::pedantic)]

use ai_radar_core::config::AppConfig;
use ai_radar_core::db::Database;
use ai_radar_core::domain::SourceType;
use ai_radar_core::pipeline::collect::run_collect;
use ai_radar_core::telemetry;
use anyhow::Context;
use clap::{Parser, Subcommand};
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
    /// Fetch RSS/Atom feeds and insert idempotent `raw_items` rows.
    Collect {
        /// Process only this source id (must be enabled and match `--source-type`).
        #[arg(long)]
        source_id: Option<Uuid>,
        /// Filter sources by discriminator (`rss` today; GitHub arrives in T-162).
        #[arg(long, default_value = "rss")]
        source_type: String,
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
        duration_secs = started.elapsed().as_secs_f64(),
        "collect job finished"
    );

    println!(
        "collected={} skipped={} errors={} ({} sources)",
        stats.collected, stats.skipped, stats.source_errors, stats.total_sources
    );

    if stats.total_sources > 0 && stats.source_errors == stats.total_sources {
        std::process::exit(1);
    }

    Ok(())
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    if cfg!(debug_assertions) {
        let _ = dotenvy::dotenv();
    }

    let cli = Cli::parse();

    match cli.command {
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
    }

    Ok(())
}
