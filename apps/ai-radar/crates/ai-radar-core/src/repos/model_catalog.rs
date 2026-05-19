//! `model_catalog_*` tables (**T-270**).

use std::collections::{BTreeMap, HashMap};

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::Row;
use uuid::Uuid;

use crate::db::{Database, RepoError, RepoResult};
use crate::domain::model_catalog::{
    ModelCatalogDiff, ModelCatalogEntry, ModelCatalogEventRow,
    ModelCatalogRunSummary,
};

/// Catalog persistence operations.
#[async_trait]
pub trait ModelCatalogRepository: Send + Sync {
    async fn load_state(&self, provider: &str) -> RepoResult<HashMap<String, ModelCatalogEntry>>;

    async fn persist_sync(
        &self,
        provider: &str,
        current: &BTreeMap<String, ModelCatalogEntry>,
        diffs: &[ModelCatalogDiff],
    ) -> RepoResult<Uuid>;

    async fn latest_run(&self, provider: &str) -> RepoResult<Option<ModelCatalogRunSummary>>;

    async fn list_recent_events(
        &self,
        provider: &str,
        limit: i64,
    ) -> RepoResult<Vec<ModelCatalogEventRow>>;
}

/// Postgres implementation.
#[derive(Debug, Clone)]
pub struct PgModelCatalogRepository {
    pool: sqlx::PgPool,
}

impl PgModelCatalogRepository {
    #[must_use]
    pub fn new(database: &Database) -> Self {
        Self {
            pool: database.pool.clone(),
        }
    }
}

#[async_trait]
impl ModelCatalogRepository for PgModelCatalogRepository {
    async fn load_state(&self, provider: &str) -> RepoResult<HashMap<String, ModelCatalogEntry>> {
        let rows = sqlx::query(
            "SELECT model_id, model_name, prompt_price, completion_price \
             FROM ai_radar.model_catalog_state WHERE provider = $1",
        )
        .bind(provider)
        .fetch_all(&self.pool)
        .await
        .map_err(RepoError::from_sqlx)?;

        Ok(rows
            .iter()
            .map(|row| -> RepoResult<(String, ModelCatalogEntry)> {
                Ok((
                    row.try_get::<String, _>("model_id")
                        .map_err(RepoError::from_sqlx)?,
                    ModelCatalogEntry {
                        model_id: row.try_get("model_id").map_err(RepoError::from_sqlx)?,
                        model_name: row.try_get("model_name").ok(),
                        prompt_price: row.try_get("prompt_price").ok(),
                        completion_price: row.try_get("completion_price").ok(),
                    },
                ))
            })
            .collect::<Result<HashMap<_, _>, RepoError>>()?)
    }

    async fn persist_sync(
        &self,
        provider: &str,
        current: &BTreeMap<String, ModelCatalogEntry>,
        diffs: &[ModelCatalogDiff],
    ) -> RepoResult<Uuid> {
        let mut tx = self.pool.begin().await.map_err(RepoError::from_sqlx)?;

        let run_id: Uuid = sqlx::query_scalar(
            "INSERT INTO ai_radar.model_catalog_runs (provider, model_count, events_count) \
             VALUES ($1, $2, $3) RETURNING id",
        )
        .bind(provider)
        .bind(i32::try_from(current.len()).unwrap_or(i32::MAX))
        .bind(i32::try_from(diffs.len()).unwrap_or(i32::MAX))
        .fetch_one(&mut *tx)
        .await
        .map_err(RepoError::from_sqlx)?;

        for diff in diffs {
            sqlx::query(
                "INSERT INTO ai_radar.model_catalog_events \
                 (run_id, model_id, event_type, prompt_price, completion_price, \
                  previous_prompt_price, previous_completion_price) \
                 VALUES ($1, $2, $3, $4, $5, $6, $7)",
            )
            .bind(run_id)
            .bind(&diff.model_id)
            .bind(diff.event_type.as_str())
            .bind(&diff.prompt_price)
            .bind(&diff.completion_price)
            .bind(&diff.previous_prompt_price)
            .bind(&diff.previous_completion_price)
            .execute(&mut *tx)
            .await
            .map_err(RepoError::from_sqlx)?;
        }

        sqlx::query("DELETE FROM ai_radar.model_catalog_state WHERE provider = $1")
            .bind(provider)
            .execute(&mut *tx)
            .await
            .map_err(RepoError::from_sqlx)?;

        for row in current.values() {
            sqlx::query(
                "INSERT INTO ai_radar.model_catalog_state \
                 (provider, model_id, model_name, prompt_price, completion_price) \
                 VALUES ($1, $2, $3, $4, $5)",
            )
            .bind(provider)
            .bind(&row.model_id)
            .bind(&row.model_name)
            .bind(&row.prompt_price)
            .bind(&row.completion_price)
            .execute(&mut *tx)
            .await
            .map_err(RepoError::from_sqlx)?;
        }

        tx.commit().await.map_err(RepoError::from_sqlx)?;
        Ok(run_id)
    }

    async fn latest_run(&self, provider: &str) -> RepoResult<Option<ModelCatalogRunSummary>> {
        let row = sqlx::query(
            "SELECT id, provider, model_count, events_count, collected_at \
             FROM ai_radar.model_catalog_runs WHERE provider = $1 \
             ORDER BY collected_at DESC LIMIT 1",
        )
        .bind(provider)
        .fetch_optional(&self.pool)
        .await
        .map_err(RepoError::from_sqlx)?;

        Ok(row.map(|r| -> RepoResult<ModelCatalogRunSummary> {
            Ok(ModelCatalogRunSummary {
                run_id: r.try_get("id").map_err(RepoError::from_sqlx)?,
                provider: r.try_get("provider").map_err(RepoError::from_sqlx)?,
                model_count: r.try_get("model_count").map_err(RepoError::from_sqlx)?,
                events_count: r.try_get("events_count").map_err(RepoError::from_sqlx)?,
                collected_at: r.try_get("collected_at").map_err(RepoError::from_sqlx)?,
            })
        }).transpose()?)
    }

    async fn list_recent_events(
        &self,
        provider: &str,
        limit: i64,
    ) -> RepoResult<Vec<ModelCatalogEventRow>> {
        let rows = sqlx::query(
            "SELECT e.id, e.run_id, e.model_id, e.event_type, e.prompt_price, e.completion_price, \
                    e.previous_prompt_price, e.previous_completion_price, e.created_at \
             FROM ai_radar.model_catalog_events e \
             JOIN ai_radar.model_catalog_runs r ON r.id = e.run_id \
             WHERE r.provider = $1 \
             ORDER BY e.created_at DESC \
             LIMIT $2",
        )
        .bind(provider)
        .bind(limit)
        .fetch_all(&self.pool)
        .await
        .map_err(RepoError::from_sqlx)?;

        rows.iter()
            .map(|row| {
                Ok(ModelCatalogEventRow {
                    id: row.try_get("id").map_err(RepoError::from_sqlx)?,
                    run_id: row.try_get("run_id").map_err(RepoError::from_sqlx)?,
                    model_id: row.try_get("model_id").map_err(RepoError::from_sqlx)?,
                    event_type: row.try_get("event_type").map_err(RepoError::from_sqlx)?,
                    prompt_price: row.try_get("prompt_price").ok(),
                    completion_price: row.try_get("completion_price").ok(),
                    previous_prompt_price: row.try_get("previous_prompt_price").ok(),
                    previous_completion_price: row.try_get("previous_completion_price").ok(),
                    created_at: row.try_get("created_at").map_err(RepoError::from_sqlx)?,
                })
            })
            .collect()
    }
}

/// Load events count from the latest run (for metrics gauge).
pub async fn load_latest_events_count(db: &Database, provider: &str) -> RepoResult<i64> {
    let count: Option<i64> = sqlx::query_scalar(
        "SELECT events_count::bigint FROM ai_radar.model_catalog_runs \
         WHERE provider = $1 ORDER BY collected_at DESC LIMIT 1",
    )
    .bind(provider)
    .fetch_optional(&db.pool)
    .await
    .map_err(RepoError::from_sqlx)?;
    Ok(count.unwrap_or(0))
}

/// Summary stats for `/stats`.
#[derive(Debug, Clone, serde::Serialize, PartialEq)]
pub struct ModelCatalogStats {
    pub provider: String,
    pub model_count: i64,
    pub events_last_run: i64,
    pub last_sync_at: Option<DateTime<Utc>>,
}

pub async fn load_model_catalog_stats(db: &Database, provider: &str) -> RepoResult<Option<ModelCatalogStats>> {
    let row = sqlx::query(
        "SELECT provider, model_count, events_count, collected_at \
         FROM ai_radar.model_catalog_runs WHERE provider = $1 \
         ORDER BY collected_at DESC LIMIT 1",
    )
    .bind(provider)
    .fetch_optional(&db.pool)
    .await
    .map_err(RepoError::from_sqlx)?;

    Ok(row.map(|r| ModelCatalogStats {
        provider: r.try_get("provider").unwrap_or_else(|_| provider.to_string()),
        model_count: r
            .try_get::<i32, _>("model_count")
            .map(i64::from)
            .unwrap_or(0),
        events_last_run: r
            .try_get::<i32, _>("events_count")
            .map(i64::from)
            .unwrap_or(0),
        last_sync_at: r.try_get("collected_at").ok(),
    }))
}
