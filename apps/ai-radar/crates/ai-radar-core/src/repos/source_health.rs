//! Aggregate source health for noise scoring (**T-238**).

use async_trait::async_trait;
use sqlx::Row;
use uuid::Uuid;

use crate::curation::source_health::snapshot_from_counts;
use crate::curation::SourceHealthSnapshot;
use crate::db::{Database, RepoError, RepoResult};

/// Load health snapshots for all sources.
#[async_trait]
pub trait SourceHealthRepository: Send + Sync {
    /// One row per source with collect/extract counters.
    async fn list_all(&self) -> RepoResult<Vec<SourceHealthSnapshot>>;

    /// Health for a single source (empty counts when missing).
    async fn get(&self, source_id: Uuid) -> RepoResult<SourceHealthSnapshot>;
}

/// Postgres aggregates over `sources`, `raw_items`, `extracted_items`.
#[derive(Debug, Clone)]
pub struct PgSourceHealthRepository {
    pool: sqlx::PgPool,
}

impl PgSourceHealthRepository {
    /// Build from a shared [`Database`].
    #[must_use]
    pub fn new(database: &Database) -> Self {
        Self {
            pool: database.pool.clone(),
        }
    }
}

const HEALTH_SQL: &str = "\
    SELECT \
        s.id, \
        s.name, \
        s.last_error, \
        COALESCE(COUNT(r.id), 0)::bigint AS raw_total, \
        COALESCE(COUNT(r.id) FILTER (WHERE r.status = 'failed'), 0)::bigint AS raw_failed, \
        COALESCE(COUNT(r.id) FILTER (WHERE r.status = 'skipped'), 0)::bigint AS raw_skipped, \
        COALESCE(COUNT(e.id), 0)::bigint AS extracted_total, \
        COALESCE( \
            COUNT(e.id) FILTER (WHERE e.metadata_json->>'quality_warn' = 'true'), \
            0 \
        )::bigint AS quality_warn \
    FROM ai_radar.sources s \
    LEFT JOIN ai_radar.raw_items r ON r.source_id = s.id \
    LEFT JOIN ai_radar.extracted_items e ON e.raw_item_id = r.id \
    WHERE ($1::uuid IS NULL OR s.id = $1) \
    GROUP BY s.id, s.name, s.last_error \
    ORDER BY s.name ASC";

fn row_to_snapshot(row: &sqlx::postgres::PgRow) -> RepoResult<SourceHealthSnapshot> {
    Ok(snapshot_from_counts(
        row.try_get("id").map_err(RepoError::from_sqlx)?,
        row.try_get("name").map_err(RepoError::from_sqlx)?,
        row.try_get("raw_total").map_err(RepoError::from_sqlx)?,
        row.try_get("raw_failed").map_err(RepoError::from_sqlx)?,
        row.try_get("raw_skipped").map_err(RepoError::from_sqlx)?,
        row.try_get("extracted_total").map_err(RepoError::from_sqlx)?,
        row.try_get("quality_warn").map_err(RepoError::from_sqlx)?,
        row.try_get("last_error").map_err(RepoError::from_sqlx)?,
    ))
}

#[async_trait]
impl SourceHealthRepository for PgSourceHealthRepository {
    async fn list_all(&self) -> RepoResult<Vec<SourceHealthSnapshot>> {
        let rows = sqlx::query(HEALTH_SQL)
            .bind(None::<Uuid>)
            .fetch_all(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
        rows.iter().map(row_to_snapshot).collect()
    }

    async fn get(&self, source_id: Uuid) -> RepoResult<SourceHealthSnapshot> {
        let row = sqlx::query(HEALTH_SQL)
            .bind(source_id)
            .fetch_optional(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?
            .ok_or(RepoError::NotFound)?;
        row_to_snapshot(&row)
    }
}
