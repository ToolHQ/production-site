//! `tool_metrics_snapshots` repository (**T-234**).

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use uuid::Uuid;

use crate::db::{Database, RepoError, RepoResult};

/// Row to insert after GitHub collect / before extract enrichment.
#[derive(Debug, Clone)]
pub struct NewToolMetricsSnapshot {
    pub tool_key: String,
    pub source_id: Option<Uuid>,
    pub stars: Option<i64>,
    pub forks: Option<i64>,
    pub open_issues: Option<i64>,
    pub collected_at: DateTime<Utc>,
}

/// Operations on popularity snapshots.
#[async_trait]
pub trait ToolMetricsSnapshotRepository: Send + Sync {
    /// Append a metrics sample (multiple per day allowed).
    async fn insert(&self, row: &NewToolMetricsSnapshot) -> RepoResult<()>;

    /// Stars count from the newest sample at or before `before` minus `window_days`.
    async fn stars_baseline(
        &self,
        tool_key: &str,
        before: DateTime<Utc>,
        window_days: i64,
    ) -> RepoResult<Option<i64>>;
}

/// Postgres implementation.
pub struct PgToolMetricsSnapshotRepository {
    pool: sqlx::PgPool,
}

impl PgToolMetricsSnapshotRepository {
    /// Build a repository from a [`Database`].
    #[must_use]
    pub fn new(database: &Database) -> Self {
        Self {
            pool: database.pool.clone(),
        }
    }
}

#[async_trait]
impl ToolMetricsSnapshotRepository for PgToolMetricsSnapshotRepository {
    async fn insert(&self, row: &NewToolMetricsSnapshot) -> RepoResult<()> {
        sqlx::query(
            "INSERT INTO ai_radar.tool_metrics_snapshots \
             (tool_key, source_id, stars, forks, open_issues, collected_at) \
             VALUES ($1, $2, $3, $4, $5, $6)",
        )
        .bind(&row.tool_key)
        .bind(row.source_id)
        .bind(row.stars)
        .bind(row.forks)
        .bind(row.open_issues)
        .bind(row.collected_at)
        .execute(&self.pool)
        .await
        .map_err(RepoError::from_sqlx)?;
        Ok(())
    }

    async fn stars_baseline(
        &self,
        tool_key: &str,
        before: DateTime<Utc>,
        window_days: i64,
    ) -> RepoResult<Option<i64>> {
        let cutoff = before - chrono::Duration::days(window_days);
        let stars: Option<i64> = sqlx::query_scalar(
            "SELECT stars FROM ai_radar.tool_metrics_snapshots \
             WHERE tool_key = $1 \
               AND collected_at <= $2 \
               AND stars IS NOT NULL \
             ORDER BY collected_at DESC \
             LIMIT 1",
        )
        .bind(tool_key)
        .bind(cutoff)
        .fetch_optional(&self.pool)
        .await
        .map_err(RepoError::from_sqlx)?;

        if stars.is_some() {
            return Ok(stars);
        }

        sqlx::query_scalar(
            "SELECT stars FROM ai_radar.tool_metrics_snapshots \
             WHERE tool_key = $1 \
               AND stars IS NOT NULL \
               AND collected_at < $2 - INTERVAL '1 day' \
             ORDER BY collected_at ASC \
             LIMIT 1",
        )
        .bind(tool_key)
        .bind(before)
        .fetch_optional(&self.pool)
        .await
        .map_err(RepoError::from_sqlx)
    }
}
