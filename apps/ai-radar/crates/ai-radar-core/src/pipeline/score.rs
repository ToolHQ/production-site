//! Deterministic scoring pass over `extracted_items` (**T-166**).

use std::time::Instant;

use crate::db::Database;
use crate::metrics;
use crate::repos::{
    ExtractedItemRepository, PgExtractedItemRepository, PgScoreRepository, ScoreRepository,
};
use crate::scorer::{Scorer, SCORING_VERSION_DETERMINISTIC_V1};

/// Default hours before a row is eligible for rescoring (unless `--rescore-all`).
pub const DEFAULT_SCORE_STALE_HOURS: i64 = 24;

/// Counters for CLI / API.
#[derive(Debug, Default, Clone, Copy)]
pub struct ScoreStats {
    /// Rows scored successfully.
    pub scored: u64,
    /// Rows that failed validation or DB insert.
    pub failed: u64,
}

/// Score up to `limit` extracted items with `deterministic-v1` rules.
///
/// # Errors
///
/// Propagates database errors from repositories.
pub async fn run_score(
    db: &Database,
    limit: i64,
    stale_hours: i64,
    rescore_all: bool,
) -> anyhow::Result<ScoreStats> {
    let started = Instant::now();
    let extracted = PgExtractedItemRepository::new(db);
    let scores = PgScoreRepository::new(db);
    let deterministic = Scorer::v1();

    let batch = extracted
        .list_pending_scoring(
            limit,
            SCORING_VERSION_DETERMINISTIC_V1,
            stale_hours,
            rescore_all,
        )
        .await?;

    let mut stats = ScoreStats::default();

    for row in batch {
        let out = deterministic.score(&row);
        let new_score = out.to_new_score(row.id);
        match scores.insert(&new_score).await {
            Ok(_) => {
                tracing::info!(
                    extracted_item_id = %row.id,
                    points = out.points,
                    decision = %out.decision.as_str(),
                    "deterministic score persisted"
                );
                stats.scored += 1;
            }
            Err(e) => {
                tracing::warn!(
                    extracted_item_id = %row.id,
                    error = %e,
                    "score insert failed"
                );
                stats.failed += 1;
            }
        }
    }

    metrics::record_score_pass(stats.scored, stats.failed, started.elapsed());
    Ok(stats)
}

/// Score one extracted row by id (reprocess / ops).
///
/// # Errors
///
/// Propagates repository or validation errors.
pub async fn score_single_extracted_item(
    db: &Database,
    extracted_item_id: uuid::Uuid,
) -> anyhow::Result<()> {
    let extracted = PgExtractedItemRepository::new(db);
    let scores = PgScoreRepository::new(db);
    let row = extracted.get(extracted_item_id).await?;
    let out = Scorer::v1().score(&row);
    let new_score = out.to_new_score(row.id);
    scores.insert(&new_score).await?;
    Ok(())
}
