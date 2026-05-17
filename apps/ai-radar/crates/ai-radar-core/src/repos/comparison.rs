//! `comparisons` repository (**T-168**).

use async_trait::async_trait;
use sqlx::Row;
use uuid::Uuid;

use crate::db::{Database, RepoError, RepoResult};
use crate::domain::{Comparison, NewComparison};

/// Persistence for comparison matrices.
#[async_trait]
pub trait ComparisonRepository: Send + Sync {
    /// Insert a new comparison snapshot.
    async fn insert(&self, payload: &NewComparison) -> RepoResult<Comparison>;

    /// Fetch by id.
    async fn get(&self, id: Uuid) -> RepoResult<Comparison>;

    /// Recent comparisons for a category.
    async fn list_recent(&self, category: Option<&str>, limit: i64) -> RepoResult<Vec<Comparison>>;
}

const SELECT_COLS: &str = "id, category, top_n, matrix_json, markdown, generated_at";

fn row_to_comparison(row: &sqlx::postgres::PgRow) -> RepoResult<Comparison> {
    Ok(Comparison {
        id: row.try_get("id").map_err(RepoError::from_sqlx)?,
        category: row.try_get("category").map_err(RepoError::from_sqlx)?,
        top_n: row.try_get("top_n").map_err(RepoError::from_sqlx)?,
        matrix_json: row.try_get("matrix_json").map_err(RepoError::from_sqlx)?,
        markdown: row.try_get("markdown").map_err(RepoError::from_sqlx)?,
        generated_at: row.try_get("generated_at").map_err(RepoError::from_sqlx)?,
    })
}

/// Postgres implementation.
#[derive(Debug, Clone)]
pub struct PgComparisonRepository {
    pool: sqlx::PgPool,
}

impl PgComparisonRepository {
    /// Wrap a shared pool.
    #[must_use]
    pub fn new(db: &Database) -> Self {
        Self {
            pool: db.pool.clone(),
        }
    }
}

#[async_trait]
impl ComparisonRepository for PgComparisonRepository {
    async fn insert(&self, payload: &NewComparison) -> RepoResult<Comparison> {
        let sql = format!(
            "INSERT INTO ai_radar.comparisons (category, top_n, matrix_json, markdown) \
             VALUES ($1, $2, $3, $4) \
             RETURNING {SELECT_COLS}"
        );
        let row = sqlx::query(&sql)
            .bind(&payload.category)
            .bind(payload.top_n)
            .bind(&payload.matrix_json)
            .bind(&payload.markdown)
            .fetch_one(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
        row_to_comparison(&row)
    }

    async fn get(&self, id: Uuid) -> RepoResult<Comparison> {
        let sql = format!("SELECT {SELECT_COLS} FROM ai_radar.comparisons WHERE id = $1");
        let row = sqlx::query(&sql)
            .bind(id)
            .fetch_optional(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?
            .ok_or(RepoError::NotFound)?;
        row_to_comparison(&row)
    }

    async fn list_recent(
        &self,
        category: Option<&str>,
        limit: i64,
    ) -> RepoResult<Vec<Comparison>> {
        let sql = format!(
            "SELECT {SELECT_COLS} FROM ai_radar.comparisons \
             WHERE ($1::text IS NULL OR category = $1) \
             ORDER BY generated_at DESC \
             LIMIT $2"
        );
        let rows = sqlx::query(&sql)
            .bind(category)
            .bind(limit)
            .fetch_all(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
        rows.iter().map(row_to_comparison).collect()
    }
}
