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
            let config = AppConfig::from_env().context("configuration")?;
            telemetry::init_tracing(&config.log_level).context("tracing")?;

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

            println!(
                "collected={} skipped={} errors={} ({} sources)",
                stats.collected, stats.skipped, stats.source_errors, stats.total_sources
            );

            if stats.total_sources > 0 && stats.source_errors == stats.total_sources {
                std::process::exit(1);
            }
        }
    }

    Ok(())
}
