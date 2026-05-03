//! Read-only aggregate counts for dashboards and `GET /stats`.

use serde::Serialize;

use crate::db::{Database, RepoError, RepoResult};

/// Row counts exposed to operators (no row payloads — cheap on small pools).
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct PipelineStats {
    /// Rows in `ai_radar.sources`.
    pub sources_total: i64,
    /// Sources with `enabled = TRUE`.
    pub sources_enabled: i64,
    /// Rows in `ai_radar.raw_items`.
    pub raw_items_total: i64,
    /// `raw_items` with `status = 'pending'` (extract queue depth).
    pub raw_items_pending: i64,
}

/// Load counts in one round-trip to Postgres (four scalar queries).
///
/// # Errors
///
/// Propagates [`RepoError`] when any query fails.
pub async fn load_pipeline_stats(db: &Database) -> RepoResult<PipelineStats> {
    let sources_total: i64 = sqlx::query_scalar("SELECT COUNT(*)::bigint FROM ai_radar.sources")
        .fetch_one(&db.pool)
        .await
        .map_err(RepoError::from_sqlx)?;
    let sources_enabled: i64 =
        sqlx::query_scalar("SELECT COUNT(*)::bigint FROM ai_radar.sources WHERE enabled = TRUE")
            .fetch_one(&db.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
    let raw_items_total: i64 =
        sqlx::query_scalar("SELECT COUNT(*)::bigint FROM ai_radar.raw_items")
            .fetch_one(&db.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
    let raw_items_pending: i64 = sqlx::query_scalar(
        "SELECT COUNT(*)::bigint FROM ai_radar.raw_items WHERE status = 'pending'",
    )
    .fetch_one(&db.pool)
    .await
    .map_err(RepoError::from_sqlx)?;

    Ok(PipelineStats {
        sources_total,
        sources_enabled,
        raw_items_total,
        raw_items_pending,
    })
}
