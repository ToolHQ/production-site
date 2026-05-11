//! `raw_items` repository.

use async_trait::async_trait;
use sqlx::Row;
use uuid::Uuid;

use crate::db::{Database, RepoError, RepoResult};
use crate::domain::{NewRawItem, RawItem, RawItemStatus};

/// Operations on `raw_items`.
#[async_trait]
pub trait RawItemRepository: Send + Sync {
    /// Idempotent insert. When `(source_id, content_hash)` already
    /// exists in the table, returns `Ok(None)` instead of erroring out
    /// — the caller can use that signal to skip extraction work.
    async fn insert_idempotent(&self, payload: &NewRawItem) -> RepoResult<Option<RawItem>>;

    /// Fetch by primary key.
    async fn get(&self, id: Uuid) -> RepoResult<RawItem>;

    /// Return the `limit` oldest pending items, ordered by
    /// `collected_at ASC` so the extractor processes upstream input
    /// FIFO.
    async fn list_pending(&self, limit: i64) -> RepoResult<Vec<RawItem>>;

    /// Count rows in `pending` status (queue depth for extract).
    async fn count_pending(&self) -> RepoResult<i64>;

    /// Update the lifecycle status.
    async fn mark_status(&self, id: Uuid, status: RawItemStatus) -> RepoResult<RawItem>;

    /// Flip up to `limit` rows from `pending` to `extracting` in one transaction
    /// (`FOR UPDATE SKIP LOCKED`), oldest `collected_at` first.
    async fn claim_pending_batch(&self, limit: i64) -> RepoResult<Vec<RawItem>>;

    /// Append a JSON object to `metadata_json.extract_attempts` (creates the array if missing).
    async fn append_extract_attempt(&self, id: Uuid, entry: serde_json::Value) -> RepoResult<()>;
}

const SELECT_COLS: &str = "id, source_id, external_id, url, title, raw_content, content_hash, \
     status, metadata_json, published_at, collected_at";

fn row_to_raw_item(row: &sqlx::postgres::PgRow) -> RepoResult<RawItem> {
    let raw_status: String = row.try_get("status").map_err(RepoError::from_sqlx)?;
    let status = RawItemStatus::parse(&raw_status)
        .map_err(|v| RepoError::Validation(format!("unknown raw_items.status '{v}'")))?;

    Ok(RawItem {
        id: row.try_get("id").map_err(RepoError::from_sqlx)?,
        source_id: row.try_get("source_id").map_err(RepoError::from_sqlx)?,
        external_id: row.try_get("external_id").map_err(RepoError::from_sqlx)?,
        url: row.try_get("url").map_err(RepoError::from_sqlx)?,
        title: row.try_get("title").map_err(RepoError::from_sqlx)?,
        raw_content: row.try_get("raw_content").map_err(RepoError::from_sqlx)?,
        content_hash: row.try_get("content_hash").map_err(RepoError::from_sqlx)?,
        status,
        metadata_json: row.try_get("metadata_json").map_err(RepoError::from_sqlx)?,
        published_at: row.try_get("published_at").map_err(RepoError::from_sqlx)?,
        collected_at: row.try_get("collected_at").map_err(RepoError::from_sqlx)?,
    })
}

/// Postgres implementation.
#[derive(Debug, Clone)]
pub struct PgRawItemRepository {
    pool: sqlx::PgPool,
}

impl PgRawItemRepository {
    /// Build a repository from a [`Database`].
    #[must_use]
    pub fn new(database: &Database) -> Self {
        Self {
            pool: database.pool.clone(),
        }
    }
}

#[async_trait]
impl RawItemRepository for PgRawItemRepository {
    async fn insert_idempotent(&self, payload: &NewRawItem) -> RepoResult<Option<RawItem>> {
        payload.validate().map_err(RepoError::Validation)?;
        let hash = payload.effective_hash();

        let sql = format!(
            "INSERT INTO ai_radar.raw_items \
                 (source_id, external_id, url, title, raw_content, content_hash, \
                  metadata_json, published_at) \
             VALUES ($1, $2, $3, $4, $5, $6, COALESCE($7, '{{}}'::jsonb), $8) \
             ON CONFLICT (source_id, content_hash) DO NOTHING \
             RETURNING {SELECT_COLS}"
        );
        let row = sqlx::query(&sql)
            .bind(payload.source_id)
            .bind(&payload.external_id)
            .bind(&payload.url)
            .bind(&payload.title)
            .bind(&payload.raw_content)
            .bind(&hash)
            .bind(payload.metadata_json.clone())
            .bind(payload.published_at)
            .fetch_optional(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;

        row.as_ref().map(row_to_raw_item).transpose()
    }

    async fn get(&self, id: Uuid) -> RepoResult<RawItem> {
        let sql = format!("SELECT {SELECT_COLS} FROM ai_radar.raw_items WHERE id = $1");
        let row = sqlx::query(&sql)
            .bind(id)
            .fetch_optional(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?
            .ok_or(RepoError::NotFound)?;
        row_to_raw_item(&row)
    }

    async fn list_pending(&self, limit: i64) -> RepoResult<Vec<RawItem>> {
        let sql = format!(
            "SELECT {SELECT_COLS} FROM ai_radar.raw_items \
             WHERE status = 'pending' \
             ORDER BY collected_at ASC \
             LIMIT $1"
        );
        let rows = sqlx::query(&sql)
            .bind(limit)
            .fetch_all(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
        rows.iter().map(row_to_raw_item).collect()
    }

    async fn count_pending(&self) -> RepoResult<i64> {
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*)::bigint FROM ai_radar.raw_items WHERE status = 'pending'",
        )
        .fetch_one(&self.pool)
        .await
        .map_err(RepoError::from_sqlx)?;
        Ok(count)
    }

    async fn mark_status(&self, id: Uuid, status: RawItemStatus) -> RepoResult<RawItem> {
        let sql = format!(
            "UPDATE ai_radar.raw_items SET status = $2 WHERE id = $1 RETURNING {SELECT_COLS}"
        );
        let row = sqlx::query(&sql)
            .bind(id)
            .bind(status.as_str())
            .fetch_optional(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?
            .ok_or(RepoError::NotFound)?;
        row_to_raw_item(&row)
    }

    async fn claim_pending_batch(&self, limit: i64) -> RepoResult<Vec<RawItem>> {
        // Qualify every column with `r.` to avoid "column reference 'id' is ambiguous"
        // when PostgreSQL sees both `raw_items AS r` and the `picked` CTE in scope.
        let returning = SELECT_COLS
            .split(", ")
            .map(|c| format!("r.{c}"))
            .collect::<Vec<_>>()
            .join(", ");
        let sql = format!(
            "WITH picked AS ( \
                 SELECT id FROM ai_radar.raw_items \
                 WHERE status = 'pending' \
                 ORDER BY collected_at ASC \
                 LIMIT $1 \
                 FOR UPDATE SKIP LOCKED \
             ) \
             UPDATE ai_radar.raw_items AS r \
             SET status = 'extracting' \
             FROM picked \
             WHERE r.id = picked.id \
             RETURNING {returning}"
        );
        let rows = sqlx::query(&sql)
            .bind(limit)
            .fetch_all(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
        rows.iter().map(row_to_raw_item).collect()
    }

    async fn append_extract_attempt(&self, id: Uuid, entry: serde_json::Value) -> RepoResult<()> {
        let res = sqlx::query(
            "UPDATE ai_radar.raw_items SET \
                 metadata_json = jsonb_set( \
                     metadata_json, \
                     '{extract_attempts}', \
                     COALESCE(metadata_json #> '{extract_attempts}', '[]'::jsonb) \
                         || jsonb_build_array($2::jsonb) \
                 ) \
             WHERE id = $1",
        )
        .bind(id)
        .bind(entry)
        .execute(&self.pool)
        .await
        .map_err(RepoError::from_sqlx)?;
        if res.rows_affected() == 0 {
            return Err(RepoError::NotFound);
        }
        Ok(())
    }
}

#[cfg(test)]
mod integration {
    use super::*;
    use crate::db::Database;
    use crate::domain::{NewSource, SourceType};
    use crate::repos::source::{PgSourceRepository, SourceRepository};

    async fn pool() -> Database {
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

    async fn seed_source(db: &Database, url: &str) -> Uuid {
        let repo = PgSourceRepository::new(db);
        repo.create(&NewSource {
            name: format!("Source for {url}"),
            source_type: SourceType::Rss,
            url: url.to_string(),
            enabled: None,
            poll_interval_minutes: None,
            metadata_json: None,
        })
        .await
        .expect("seed source")
        .id
    }

    #[tokio::test]
    #[ignore = "requires Postgres; run with --ignored"]
    async fn idempotent_insert_returns_some_then_none() {
        let db = pool().await;
        cleanup(&db.pool).await;
        let source_id = seed_source(&db, "https://feed.example.com/raw1.xml").await;

        let repo = PgRawItemRepository::new(&db);
        let item = NewRawItem {
            source_id,
            external_id: Some("ext-1".into()),
            url: "https://x.example.com/post-1".into(),
            title: Some("Post 1".into()),
            raw_content: "hello world".into(),
            content_hash: None,
            metadata_json: None,
            published_at: None,
        };

        let first = repo.insert_idempotent(&item).await.expect("first insert");
        assert!(first.is_some(), "first insert must materialize");
        let inserted = first.unwrap();
        assert_eq!(inserted.status, RawItemStatus::Pending);

        let second = repo.insert_idempotent(&item).await.expect("second insert");
        assert!(second.is_none(), "second insert must be skipped");

        cleanup(&db.pool).await;
    }

    #[tokio::test]
    #[ignore = "requires Postgres; run with --ignored"]
    async fn list_pending_then_mark_status() {
        let db = pool().await;
        cleanup(&db.pool).await;
        let source_id = seed_source(&db, "https://feed.example.com/raw2.xml").await;
        let repo = PgRawItemRepository::new(&db);

        for n in 0..3 {
            repo.insert_idempotent(&NewRawItem {
                source_id,
                external_id: Some(format!("ext-{n}")),
                url: format!("https://x.example.com/p-{n}"),
                title: None,
                raw_content: format!("content-{n}"),
                content_hash: None,
                metadata_json: None,
                published_at: None,
            })
            .await
            .expect("insert");
        }

        let pending = repo.list_pending(10).await.expect("list_pending");
        assert_eq!(pending.len(), 3);

        let updated = repo
            .mark_status(pending[0].id, RawItemStatus::Extracting)
            .await
            .expect("mark_status");
        assert_eq!(updated.status, RawItemStatus::Extracting);

        let still_pending = repo
            .list_pending(10)
            .await
            .expect("list_pending after mark");
        assert_eq!(still_pending.len(), 2);

        assert_eq!(repo.count_pending().await.expect("count_pending"), 2);

        cleanup(&db.pool).await;
    }
}
