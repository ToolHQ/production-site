//! `extracted_items` repository.

use async_trait::async_trait;
use sqlx::Row;
use uuid::Uuid;

use crate::db::{Database, RepoError, RepoResult};
use crate::domain::{ExtractedItem, Maturity, NewExtractedItem, RiskLevel};

/// Operations on `extracted_items`.
#[async_trait]
pub trait ExtractedItemRepository: Send + Sync {
    /// Insert a new extracted item. When `payload.version` is `None` the
    /// implementation picks the next free integer for the
    /// `(raw_item_id, version)` UNIQUE constraint.
    async fn insert(&self, payload: &NewExtractedItem) -> RepoResult<ExtractedItem>;

    /// Fetch the latest version for a given `raw_item_id`. Returns
    /// [`RepoError::NotFound`] when the raw item has not been extracted
    /// yet.
    async fn get_latest_for_raw_item(&self, raw_item_id: Uuid) -> RepoResult<ExtractedItem>;

    /// Fetch by primary key.
    async fn get(&self, id: Uuid) -> RepoResult<ExtractedItem>;

    /// Rows due for scoring with `scoring_version` (FIFO by `created_at`).
    ///
    /// When `rescore_all` is true, returns the oldest `limit` rows regardless of
    /// recent scores. Otherwise returns rows with **no** score for `scoring_version`
    /// or whose **latest** such score is older than `stale_hours` hours.
    async fn list_pending_scoring(
        &self,
        limit: i64,
        scoring_version: &str,
        stale_hours: i64,
        rescore_all: bool,
    ) -> RepoResult<Vec<ExtractedItem>>;
}

const SELECT_COLS: &str = "id, raw_item_id, version, extractor, tool_name, category, summary, \
     problem_solved, self_hosted, saas_only, license, maturity, risk_level, stack_fit, \
     metadata_json, created_at";

fn row_to_extracted_item(row: &sqlx::postgres::PgRow) -> RepoResult<ExtractedItem> {
    let maturity_raw: Option<String> = row.try_get("maturity").map_err(RepoError::from_sqlx)?;
    let maturity = match maturity_raw {
        Some(v) => Some(Maturity::parse(&v).map_err(|x| {
            RepoError::Validation(format!("unknown extracted_items.maturity '{x}'"))
        })?),
        None => None,
    };
    let risk_raw: Option<String> = row.try_get("risk_level").map_err(RepoError::from_sqlx)?;
    let risk_level = match risk_raw {
        Some(v) => Some(RiskLevel::parse(&v).map_err(|x| {
            RepoError::Validation(format!("unknown extracted_items.risk_level '{x}'"))
        })?),
        None => None,
    };

    Ok(ExtractedItem {
        id: row.try_get("id").map_err(RepoError::from_sqlx)?,
        raw_item_id: row.try_get("raw_item_id").map_err(RepoError::from_sqlx)?,
        version: row.try_get("version").map_err(RepoError::from_sqlx)?,
        extractor: row.try_get("extractor").map_err(RepoError::from_sqlx)?,
        tool_name: row.try_get("tool_name").map_err(RepoError::from_sqlx)?,
        category: row.try_get("category").map_err(RepoError::from_sqlx)?,
        summary: row.try_get("summary").map_err(RepoError::from_sqlx)?,
        problem_solved: row
            .try_get("problem_solved")
            .map_err(RepoError::from_sqlx)?,
        self_hosted: row.try_get("self_hosted").map_err(RepoError::from_sqlx)?,
        saas_only: row.try_get("saas_only").map_err(RepoError::from_sqlx)?,
        license: row.try_get("license").map_err(RepoError::from_sqlx)?,
        maturity,
        risk_level,
        stack_fit: row.try_get("stack_fit").map_err(RepoError::from_sqlx)?,
        metadata_json: row.try_get("metadata_json").map_err(RepoError::from_sqlx)?,
        created_at: row.try_get("created_at").map_err(RepoError::from_sqlx)?,
    })
}

/// Postgres implementation.
#[derive(Debug, Clone)]
pub struct PgExtractedItemRepository {
    pool: sqlx::PgPool,
}

impl PgExtractedItemRepository {
    /// Build a repository from a [`Database`].
    #[must_use]
    pub fn new(database: &Database) -> Self {
        Self {
            pool: database.pool.clone(),
        }
    }
}

#[async_trait]
impl ExtractedItemRepository for PgExtractedItemRepository {
    async fn insert(&self, payload: &NewExtractedItem) -> RepoResult<ExtractedItem> {
        if payload.extractor.trim().is_empty() {
            return Err(RepoError::Validation("extractor must not be empty".into()));
        }

        // Auto-assign next version when the caller did not pin one.
        let resolved_version: i32 = match payload.version {
            Some(v) if v >= 1 => v,
            Some(v) => {
                return Err(RepoError::Validation(format!(
                    "version must be >= 1, got {v}"
                )))
            }
            None => {
                let row = sqlx::query(
                    "SELECT COALESCE(MAX(version), 0) + 1 AS next_version \
                     FROM ai_radar.extracted_items WHERE raw_item_id = $1",
                )
                .bind(payload.raw_item_id)
                .fetch_one(&self.pool)
                .await
                .map_err(RepoError::from_sqlx)?;
                row.try_get("next_version").map_err(RepoError::from_sqlx)?
            }
        };

        let sql = format!(
            "INSERT INTO ai_radar.extracted_items \
                 (raw_item_id, version, extractor, tool_name, category, summary, problem_solved, \
                  self_hosted, saas_only, license, maturity, risk_level, stack_fit, metadata_json) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, \
                     COALESCE($14, '{{}}'::jsonb)) \
             RETURNING {SELECT_COLS}"
        );
        let row = sqlx::query(&sql)
            .bind(payload.raw_item_id)
            .bind(resolved_version)
            .bind(&payload.extractor)
            .bind(&payload.tool_name)
            .bind(&payload.category)
            .bind(&payload.summary)
            .bind(&payload.problem_solved)
            .bind(payload.self_hosted)
            .bind(payload.saas_only)
            .bind(&payload.license)
            .bind(payload.maturity.map(Maturity::as_str))
            .bind(payload.risk_level.map(RiskLevel::as_str))
            .bind(&payload.stack_fit)
            .bind(payload.metadata_json.clone())
            .fetch_one(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;

        row_to_extracted_item(&row)
    }

    async fn get_latest_for_raw_item(&self, raw_item_id: Uuid) -> RepoResult<ExtractedItem> {
        let sql = format!(
            "SELECT {SELECT_COLS} FROM ai_radar.extracted_items \
             WHERE raw_item_id = $1 ORDER BY version DESC LIMIT 1"
        );
        let row = sqlx::query(&sql)
            .bind(raw_item_id)
            .fetch_optional(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?
            .ok_or(RepoError::NotFound)?;
        row_to_extracted_item(&row)
    }

    async fn get(&self, id: Uuid) -> RepoResult<ExtractedItem> {
        let sql = format!("SELECT {SELECT_COLS} FROM ai_radar.extracted_items WHERE id = $1");
        let row = sqlx::query(&sql)
            .bind(id)
            .fetch_optional(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?
            .ok_or(RepoError::NotFound)?;
        row_to_extracted_item(&row)
    }

    async fn list_pending_scoring(
        &self,
        limit: i64,
        scoring_version: &str,
        stale_hours: i64,
        rescore_all: bool,
    ) -> RepoResult<Vec<ExtractedItem>> {
        let sql = format!(
            "SELECT {SELECT_COLS} FROM ai_radar.extracted_items ei \
             WHERE ($4::bool OR ( \
                 COALESCE(( \
                     SELECT MAX(s.created_at) FROM ai_radar.scores s \
                     WHERE s.extracted_item_id = ei.id AND s.scoring_version = $1 \
                 ), 'epoch'::timestamptz) < (CURRENT_TIMESTAMP - ($2::bigint * INTERVAL '1 hour')) \
             )) \
             ORDER BY ei.created_at ASC \
             LIMIT $3"
        );
        let rows = sqlx::query(&sql)
            .bind(scoring_version)
            .bind(stale_hours)
            .bind(limit)
            .bind(rescore_all)
            .fetch_all(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
        rows.iter().map(row_to_extracted_item).collect()
    }
}

#[cfg(test)]
mod integration {
    use super::*;
    use crate::db::Database;
    use crate::domain::{NewRawItem, NewSource, SourceType};
    use crate::repos::raw_item::{PgRawItemRepository, RawItemRepository};
    use crate::repos::source::{PgSourceRepository, SourceRepository};

    async fn db_handle() -> Database {
        let url =
            std::env::var("DATABASE_URL").expect("DATABASE_URL must be set for ignored tests");
        Database::connect(&url).await.expect("connect")
    }

    async fn cleanup(pool: &sqlx::PgPool) {
        sqlx::query("TRUNCATE ai_radar.sources CASCADE")
            .execute(pool)
            .await
            .expect("cleanup");
    }

    async fn seed(db: &Database, url: &str) -> Uuid {
        let src = PgSourceRepository::new(db)
            .create(&NewSource {
                name: "src".into(),
                source_type: SourceType::Rss,
                url: format!("{url}/feed.xml"),
                enabled: None,
                poll_interval_minutes: None,
                metadata_json: None,
            })
            .await
            .expect("source")
            .id;
        PgRawItemRepository::new(db)
            .insert_idempotent(&NewRawItem {
                source_id: src,
                external_id: None,
                url: format!("{url}/p"),
                title: None,
                raw_content: format!("c-{url}"),
                content_hash: None,
                metadata_json: None,
                published_at: None,
            })
            .await
            .expect("raw")
            .expect("inserted")
            .id
    }

    #[tokio::test]
    #[ignore = "requires Postgres; run with --ignored"]
    async fn version_auto_increments_on_reprocess() {
        let db = db_handle().await;
        cleanup(&db.pool).await;
        let raw_id = seed(&db, "https://reprocess.example.com").await;
        let repo = PgExtractedItemRepository::new(&db);

        let v1 = repo
            .insert(&NewExtractedItem {
                raw_item_id: raw_id,
                version: None,
                extractor: "deterministic-v1".into(),
                ..Default::default()
            })
            .await
            .expect("insert v1");
        assert_eq!(v1.version, 1);

        let v2 = repo
            .insert(&NewExtractedItem {
                raw_item_id: raw_id,
                version: None,
                extractor: "deterministic-v1".into(),
                ..Default::default()
            })
            .await
            .expect("insert v2");
        assert_eq!(v2.version, 2);

        let latest = repo.get_latest_for_raw_item(raw_id).await.expect("latest");
        assert_eq!(latest.version, 2);

        cleanup(&db.pool).await;
    }
}
