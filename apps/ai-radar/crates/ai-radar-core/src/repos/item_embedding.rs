//! `item_embeddings` repository (**T-247**).

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde_json::json;
use sqlx::Row;
use uuid::Uuid;

use crate::db::{Database, RepoError, RepoResult};

/// Persisted embedding row.
#[derive(Debug, Clone, PartialEq)]
pub struct ItemEmbedding {
    pub id: Uuid,
    pub extracted_item_id: Uuid,
    pub model: String,
    pub dimensions: i32,
    pub vector: Vec<f32>,
    pub created_at: DateTime<Utc>,
}

/// Insert payload.
#[derive(Debug, Clone)]
pub struct NewItemEmbedding {
    pub extracted_item_id: Uuid,
    pub model: String,
    pub dimensions: i32,
    pub vector: Vec<f32>,
}

/// Storage for semantic vectors.
#[async_trait]
pub trait ItemEmbeddingRepository: Send + Sync {
    /// Upsert by `(extracted_item_id, model)`.
    async fn upsert(&self, payload: &NewItemEmbedding) -> RepoResult<ItemEmbedding>;

    /// Latest embedding for an extracted item (any model).
    async fn get_latest(&self, extracted_item_id: Uuid) -> RepoResult<Option<ItemEmbedding>>;

    /// List embeddings for cosine search (bounded).
    async fn list_for_search(
        &self,
        model: &str,
        limit: i64,
        category: Option<&str>,
    ) -> RepoResult<Vec<ItemEmbedding>>;
}

/// Postgres implementation.
#[derive(Debug, Clone)]
pub struct PgItemEmbeddingRepository {
    pool: sqlx::PgPool,
}

impl PgItemEmbeddingRepository {
    /// Build from shared [`Database`].
    #[must_use]
    pub fn new(database: &Database) -> Self {
        Self {
            pool: database.pool.clone(),
        }
    }
}

fn vector_to_json(v: &[f32]) -> serde_json::Value {
    json!(v)
}

fn json_to_vector(v: serde_json::Value) -> RepoResult<Vec<f32>> {
    match v {
        serde_json::Value::Array(items) => items
            .into_iter()
            .map(|x| {
                x.as_f64()
                    .map(|f| f as f32)
                    .ok_or_else(|| RepoError::Validation("embedding vector element not numeric".into()))
            })
            .collect(),
        _ => Err(RepoError::Validation(
            "embedding vector must be a JSON array".into(),
        )),
    }
}

fn row_to_embedding(row: &sqlx::postgres::PgRow) -> RepoResult<ItemEmbedding> {
    let vector_json: serde_json::Value = row.try_get("vector").map_err(RepoError::from_sqlx)?;
    Ok(ItemEmbedding {
        id: row.try_get("id").map_err(RepoError::from_sqlx)?,
        extracted_item_id: row
            .try_get("extracted_item_id")
            .map_err(RepoError::from_sqlx)?,
        model: row.try_get("model").map_err(RepoError::from_sqlx)?,
        dimensions: row.try_get("dimensions").map_err(RepoError::from_sqlx)?,
        vector: json_to_vector(vector_json)?,
        created_at: row.try_get("created_at").map_err(RepoError::from_sqlx)?,
    })
}

#[async_trait]
impl ItemEmbeddingRepository for PgItemEmbeddingRepository {
    async fn upsert(&self, payload: &NewItemEmbedding) -> RepoResult<ItemEmbedding> {
        let row = sqlx::query(
            "INSERT INTO ai_radar.item_embeddings \
             (extracted_item_id, model, dimensions, vector) \
             VALUES ($1, $2, $3, $4) \
             ON CONFLICT (extracted_item_id, model) DO UPDATE \
             SET dimensions = EXCLUDED.dimensions, \
                 vector = EXCLUDED.vector, \
                 created_at = now() \
             RETURNING id, extracted_item_id, model, dimensions, vector, created_at",
        )
        .bind(payload.extracted_item_id)
        .bind(&payload.model)
        .bind(payload.dimensions)
        .bind(vector_to_json(&payload.vector))
        .fetch_one(&self.pool)
        .await
        .map_err(RepoError::from_sqlx)?;
        row_to_embedding(&row)
    }

    async fn get_latest(&self, extracted_item_id: Uuid) -> RepoResult<Option<ItemEmbedding>> {
        let row = sqlx::query(
            "SELECT id, extracted_item_id, model, dimensions, vector, created_at \
             FROM ai_radar.item_embeddings \
             WHERE extracted_item_id = $1 \
             ORDER BY created_at DESC \
             LIMIT 1",
        )
        .bind(extracted_item_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(RepoError::from_sqlx)?;
        row.as_ref().map(row_to_embedding).transpose()
    }

    async fn list_for_search(
        &self,
        model: &str,
        limit: i64,
        category: Option<&str>,
    ) -> RepoResult<Vec<ItemEmbedding>> {
        let limit = limit.clamp(1, 500);
        let rows = sqlx::query(
            "SELECT ie.id, ie.extracted_item_id, ie.model, ie.dimensions, ie.vector, ie.created_at \
             FROM ai_radar.item_embeddings ie \
             JOIN ai_radar.extracted_items ei ON ei.id = ie.extracted_item_id \
             WHERE ie.model = $1 \
               AND ($2::text IS NULL OR ei.category = $2) \
             ORDER BY ie.created_at DESC \
             LIMIT $3",
        )
        .bind(model)
        .bind(category)
        .bind(limit)
        .fetch_all(&self.pool)
        .await
        .map_err(RepoError::from_sqlx)?;
        rows.iter().map(row_to_embedding).collect()
    }
}
