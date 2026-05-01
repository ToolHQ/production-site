//! `sources` repository.

use async_trait::async_trait;
use sqlx::Row;
use uuid::Uuid;

use crate::db::{Database, RepoError, RepoResult};
use crate::domain::{NewSource, Source, SourceType, SourceUpdate};

/// Operations needed by the rest of the codebase to manage sources.
#[async_trait]
pub trait SourceRepository: Send + Sync {
    /// Return every source flagged `enabled = TRUE`, ordered by `name`.
    async fn list_enabled(&self) -> RepoResult<Vec<Source>>;

    /// Return every source regardless of `enabled`, ordered by `name`.
    async fn list_all(&self) -> RepoResult<Vec<Source>>;

    /// Fetch by primary key. Returns [`RepoError::NotFound`] when missing.
    async fn get(&self, id: Uuid) -> RepoResult<Source>;

    /// Insert a new source. Returns [`RepoError::Conflict`] when the
    /// `(source_type, url)` UNIQUE constraint trips.
    async fn create(&self, payload: &NewSource) -> RepoResult<Source>;

    /// Apply a patch to an existing source. Returns [`RepoError::NotFound`]
    /// if the row does not exist.
    async fn update(&self, id: Uuid, patch: &SourceUpdate) -> RepoResult<Source>;

    /// Toggle the `enabled` flag.
    async fn set_enabled(&self, id: Uuid, enabled: bool) -> RepoResult<Source>;

    /// Persist the result of a poll attempt. `error` is `None` on success.
    async fn touch_polled(&self, id: Uuid, error: Option<&str>) -> RepoResult<()>;
}

/// Postgres implementation backed by the shared [`Database`] pool.
#[derive(Debug, Clone)]
pub struct PgSourceRepository {
    pool: sqlx::PgPool,
}

impl PgSourceRepository {
    /// Build a repository from a [`Database`].
    #[must_use]
    pub fn new(database: &Database) -> Self {
        Self {
            pool: database.pool.clone(),
        }
    }
}

const SELECT_COLS: &str = "id, name, source_type, url, enabled, poll_interval_minutes, \
     last_polled_at, last_error, metadata_json, created_at, updated_at";

fn row_to_source(row: &sqlx::postgres::PgRow) -> RepoResult<Source> {
    let raw_type: String = row.try_get("source_type").map_err(RepoError::from_sqlx)?;
    let source_type = SourceType::parse(&raw_type)
        .map_err(|v| RepoError::Validation(format!("unknown source_type '{v}'")))?;

    Ok(Source {
        id: row.try_get("id").map_err(RepoError::from_sqlx)?,
        name: row.try_get("name").map_err(RepoError::from_sqlx)?,
        source_type,
        url: row.try_get("url").map_err(RepoError::from_sqlx)?,
        enabled: row.try_get("enabled").map_err(RepoError::from_sqlx)?,
        poll_interval_minutes: row
            .try_get("poll_interval_minutes")
            .map_err(RepoError::from_sqlx)?,
        last_polled_at: row
            .try_get("last_polled_at")
            .map_err(RepoError::from_sqlx)?,
        last_error: row.try_get("last_error").map_err(RepoError::from_sqlx)?,
        metadata_json: row.try_get("metadata_json").map_err(RepoError::from_sqlx)?,
        created_at: row.try_get("created_at").map_err(RepoError::from_sqlx)?,
        updated_at: row.try_get("updated_at").map_err(RepoError::from_sqlx)?,
    })
}

#[async_trait]
impl SourceRepository for PgSourceRepository {
    async fn list_enabled(&self) -> RepoResult<Vec<Source>> {
        let sql = format!(
            "SELECT {SELECT_COLS} FROM ai_radar.sources WHERE enabled = TRUE ORDER BY name ASC"
        );
        let rows = sqlx::query(&sql)
            .fetch_all(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
        rows.iter().map(row_to_source).collect()
    }

    async fn list_all(&self) -> RepoResult<Vec<Source>> {
        let sql = format!("SELECT {SELECT_COLS} FROM ai_radar.sources ORDER BY name ASC");
        let rows = sqlx::query(&sql)
            .fetch_all(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
        rows.iter().map(row_to_source).collect()
    }

    async fn get(&self, id: Uuid) -> RepoResult<Source> {
        let sql = format!("SELECT {SELECT_COLS} FROM ai_radar.sources WHERE id = $1");
        let row = sqlx::query(&sql)
            .bind(id)
            .fetch_optional(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?
            .ok_or(RepoError::NotFound)?;
        row_to_source(&row)
    }

    async fn create(&self, payload: &NewSource) -> RepoResult<Source> {
        payload.validate().map_err(RepoError::Validation)?;

        let sql = format!(
            "INSERT INTO ai_radar.sources \
                 (name, source_type, url, enabled, poll_interval_minutes, metadata_json) \
             VALUES ($1, $2, $3, COALESCE($4, TRUE), COALESCE($5, 30), COALESCE($6, '{{}}'::jsonb)) \
             RETURNING {SELECT_COLS}"
        );
        let row = sqlx::query(&sql)
            .bind(&payload.name)
            .bind(payload.source_type.as_str())
            .bind(&payload.url)
            .bind(payload.enabled)
            .bind(payload.poll_interval_minutes)
            .bind(payload.metadata_json.clone())
            .fetch_one(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;

        row_to_source(&row)
    }

    async fn update(&self, id: Uuid, patch: &SourceUpdate) -> RepoResult<Source> {
        if let Some(p) = patch.poll_interval_minutes {
            if !(1..=1440).contains(&p) {
                return Err(RepoError::Validation(format!(
                    "poll_interval_minutes must be in [1, 1440], got {p}"
                )));
            }
        }

        // COALESCE-based partial update keeps the SQL static. Each NULL
        // placeholder leaves the column untouched.
        let sql = format!(
            "UPDATE ai_radar.sources SET \
                 name                  = COALESCE($2, name), \
                 url                   = COALESCE($3, url), \
                 enabled               = COALESCE($4, enabled), \
                 poll_interval_minutes = COALESCE($5, poll_interval_minutes), \
                 metadata_json         = COALESCE($6, metadata_json) \
             WHERE id = $1 \
             RETURNING {SELECT_COLS}"
        );
        let row = sqlx::query(&sql)
            .bind(id)
            .bind(&patch.name)
            .bind(&patch.url)
            .bind(patch.enabled)
            .bind(patch.poll_interval_minutes)
            .bind(patch.metadata_json.clone())
            .fetch_optional(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?
            .ok_or(RepoError::NotFound)?;

        row_to_source(&row)
    }

    async fn set_enabled(&self, id: Uuid, enabled: bool) -> RepoResult<Source> {
        let sql = format!(
            "UPDATE ai_radar.sources SET enabled = $2 WHERE id = $1 RETURNING {SELECT_COLS}"
        );
        let row = sqlx::query(&sql)
            .bind(id)
            .bind(enabled)
            .fetch_optional(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?
            .ok_or(RepoError::NotFound)?;
        row_to_source(&row)
    }

    async fn touch_polled(&self, id: Uuid, error: Option<&str>) -> RepoResult<()> {
        let sql = "UPDATE ai_radar.sources \
             SET last_polled_at = now(), last_error = $2 \
             WHERE id = $1";
        let result = sqlx::query(sql)
            .bind(id)
            .bind(error)
            .execute(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
        if result.rows_affected() == 0 {
            return Err(RepoError::NotFound);
        }
        Ok(())
    }
}

// ─── Integration tests ───────────────────────────────────────────────────
//
// These tests touch a real Postgres. They are `#[ignore]` so the standard
// `cargo test` invocation (and the harness `rust-ai-radar` gate) runs
// cleanly without a database. To execute them:
//
//   docker compose up -d postgres
//   sqlx migrate run --source migrations
//   DATABASE_URL='postgres://ai_radar:ai_radar@127.0.0.1:15432/ai_radar?options=-csearch_path%3Dpublic' \
//       cargo test --workspace -- --ignored --test-threads=1
#[cfg(test)]
mod integration {
    use super::*;
    use crate::db::Database;

    async fn pool() -> Database {
        let url =
            std::env::var("DATABASE_URL").expect("DATABASE_URL must be set for ignored tests");
        Database::connect(&url)
            .await
            .expect("failed to connect to DATABASE_URL")
    }

    async fn cleanup(pool: &sqlx::PgPool) {
        sqlx::query("TRUNCATE ai_radar.sources CASCADE")
            .execute(pool)
            .await
            .expect("cleanup failed");
    }

    #[tokio::test]
    #[ignore = "requires Postgres; run with --ignored"]
    async fn crud_roundtrip() {
        let db = pool().await;
        let repo = PgSourceRepository::new(&db);
        cleanup(&db.pool).await;

        let created = repo
            .create(&NewSource {
                name: "Hugging Face Blog".into(),
                source_type: SourceType::Rss,
                url: "https://huggingface.co/blog/feed.xml".into(),
                enabled: Some(true),
                poll_interval_minutes: Some(60),
                metadata_json: None,
            })
            .await
            .expect("create");

        let fetched = repo.get(created.id).await.expect("get");
        assert_eq!(fetched.name, "Hugging Face Blog");
        assert_eq!(fetched.source_type, SourceType::Rss);
        assert_eq!(fetched.poll_interval_minutes, 60);

        let updated = repo
            .update(
                created.id,
                &SourceUpdate {
                    name: Some("HF Blog".into()),
                    poll_interval_minutes: Some(30),
                    ..Default::default()
                },
            )
            .await
            .expect("update");
        assert_eq!(updated.name, "HF Blog");
        assert_eq!(updated.poll_interval_minutes, 30);

        let toggled = repo.set_enabled(created.id, false).await.expect("disable");
        assert!(!toggled.enabled);

        let listed = repo.list_enabled().await.expect("list_enabled");
        assert!(listed.iter().all(|s| s.id != created.id));

        let listed_all = repo.list_all().await.expect("list_all");
        assert!(listed_all.iter().any(|s| s.id == created.id));

        cleanup(&db.pool).await;
    }

    #[tokio::test]
    #[ignore = "requires Postgres; run with --ignored"]
    async fn unique_url_violation_returns_conflict() {
        let db = pool().await;
        let repo = PgSourceRepository::new(&db);
        cleanup(&db.pool).await;

        let payload = NewSource {
            name: "Duplicate".into(),
            source_type: SourceType::Rss,
            url: "https://dup.example.com/feed.xml".into(),
            enabled: None,
            poll_interval_minutes: None,
            metadata_json: None,
        };
        repo.create(&payload).await.expect("first insert");
        let err = repo.create(&payload).await.expect_err("expected conflict");
        match err {
            RepoError::Conflict(msg) => assert!(msg.contains("sources_url_source_type_uidx")),
            other => panic!("expected Conflict, got {other:?}"),
        }

        cleanup(&db.pool).await;
    }

    #[tokio::test]
    #[ignore = "requires Postgres; run with --ignored"]
    async fn validation_blocks_blank_name() {
        let db = pool().await;
        let repo = PgSourceRepository::new(&db);

        let err = repo
            .create(&NewSource {
                name: "  ".into(),
                source_type: SourceType::Rss,
                url: "https://x.example.com".into(),
                enabled: None,
                poll_interval_minutes: None,
                metadata_json: None,
            })
            .await
            .expect_err("expected validation");
        match err {
            RepoError::Validation(msg) => assert!(msg.contains("name")),
            other => panic!("expected Validation, got {other:?}"),
        }
    }

    #[tokio::test]
    #[ignore = "requires Postgres; run with --ignored"]
    async fn touch_polled_records_error() {
        let db = pool().await;
        let repo = PgSourceRepository::new(&db);
        cleanup(&db.pool).await;

        let created = repo
            .create(&NewSource {
                name: "Touch test".into(),
                source_type: SourceType::Rss,
                url: "https://touch.example.com/feed.xml".into(),
                enabled: None,
                poll_interval_minutes: None,
                metadata_json: None,
            })
            .await
            .expect("create");

        repo.touch_polled(created.id, Some("network timeout"))
            .await
            .expect("touch with error");
        let after = repo.get(created.id).await.expect("get");
        assert_eq!(after.last_error.as_deref(), Some("network timeout"));
        assert!(after.last_polled_at.is_some());

        cleanup(&db.pool).await;
    }
}
