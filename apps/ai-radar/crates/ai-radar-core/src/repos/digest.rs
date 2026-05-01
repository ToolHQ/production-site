//! `digests` repository.

use async_trait::async_trait;
use sqlx::Row;
use uuid::Uuid;

use crate::db::{Database, RepoError, RepoResult};
use crate::domain::{Digest, DigestType, NewDigest};

/// Operations on `digests`.
#[async_trait]
pub trait DigestRepository: Send + Sync {
    /// Insert a digest record.
    async fn insert(&self, payload: &NewDigest) -> RepoResult<Digest>;

    /// Fetch by primary key.
    async fn get(&self, id: Uuid) -> RepoResult<Digest>;

    /// Most recent digests, newest first.
    async fn list_recent(&self, limit: i64) -> RepoResult<Vec<Digest>>;

    /// Most recent digests filtered by cadence.
    async fn list_recent_by_type(
        &self,
        digest_type: DigestType,
        limit: i64,
    ) -> RepoResult<Vec<Digest>>;
}

const SELECT_COLS: &str = "id, digest_type, period_start, period_end, markdown_content, \
     metadata_json, generated_at";

fn row_to_digest(row: &sqlx::postgres::PgRow) -> RepoResult<Digest> {
    let raw_type: String = row.try_get("digest_type").map_err(RepoError::from_sqlx)?;
    let digest_type = DigestType::parse(&raw_type)
        .map_err(|v| RepoError::Validation(format!("unknown digests.digest_type '{v}'")))?;

    Ok(Digest {
        id: row.try_get("id").map_err(RepoError::from_sqlx)?,
        digest_type,
        period_start: row.try_get("period_start").map_err(RepoError::from_sqlx)?,
        period_end: row.try_get("period_end").map_err(RepoError::from_sqlx)?,
        markdown_content: row
            .try_get("markdown_content")
            .map_err(RepoError::from_sqlx)?,
        metadata_json: row.try_get("metadata_json").map_err(RepoError::from_sqlx)?,
        generated_at: row.try_get("generated_at").map_err(RepoError::from_sqlx)?,
    })
}

/// Postgres implementation.
#[derive(Debug, Clone)]
pub struct PgDigestRepository {
    pool: sqlx::PgPool,
}

impl PgDigestRepository {
    /// Build a repository from a [`Database`].
    #[must_use]
    pub fn new(database: &Database) -> Self {
        Self {
            pool: database.pool.clone(),
        }
    }
}

#[async_trait]
impl DigestRepository for PgDigestRepository {
    async fn insert(&self, payload: &NewDigest) -> RepoResult<Digest> {
        payload.validate().map_err(RepoError::Validation)?;
        let sql = format!(
            "INSERT INTO ai_radar.digests \
                 (digest_type, period_start, period_end, markdown_content, metadata_json) \
             VALUES ($1, $2, $3, $4, COALESCE($5, '{{}}'::jsonb)) \
             RETURNING {SELECT_COLS}"
        );
        let row = sqlx::query(&sql)
            .bind(payload.digest_type.as_str())
            .bind(payload.period_start)
            .bind(payload.period_end)
            .bind(&payload.markdown_content)
            .bind(payload.metadata_json.clone())
            .fetch_one(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
        row_to_digest(&row)
    }

    async fn get(&self, id: Uuid) -> RepoResult<Digest> {
        let sql = format!("SELECT {SELECT_COLS} FROM ai_radar.digests WHERE id = $1");
        let row = sqlx::query(&sql)
            .bind(id)
            .fetch_optional(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?
            .ok_or(RepoError::NotFound)?;
        row_to_digest(&row)
    }

    async fn list_recent(&self, limit: i64) -> RepoResult<Vec<Digest>> {
        let sql = format!(
            "SELECT {SELECT_COLS} FROM ai_radar.digests ORDER BY generated_at DESC LIMIT $1"
        );
        let rows = sqlx::query(&sql)
            .bind(limit)
            .fetch_all(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
        rows.iter().map(row_to_digest).collect()
    }

    async fn list_recent_by_type(
        &self,
        digest_type: DigestType,
        limit: i64,
    ) -> RepoResult<Vec<Digest>> {
        let sql = format!(
            "SELECT {SELECT_COLS} FROM ai_radar.digests \
             WHERE digest_type = $1 ORDER BY period_start DESC LIMIT $2"
        );
        let rows = sqlx::query(&sql)
            .bind(digest_type.as_str())
            .bind(limit)
            .fetch_all(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
        rows.iter().map(row_to_digest).collect()
    }
}
