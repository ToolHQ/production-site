//! `feedback` repository.

use async_trait::async_trait;
use sqlx::Row;
use uuid::Uuid;

use crate::db::{Database, RepoError, RepoResult};
use crate::domain::{Feedback, FeedbackType, NewFeedback};

/// Operations on `feedback`.
#[async_trait]
pub trait FeedbackRepository: Send + Sync {
    /// Append a feedback entry.
    async fn insert(&self, payload: &NewFeedback) -> RepoResult<Feedback>;

    /// Return every feedback for an extracted item, newest first.
    async fn list_for_item(&self, extracted_item_id: Uuid) -> RepoResult<Vec<Feedback>>;
}

const SELECT_COLS: &str = "id, extracted_item_id, feedback_type, notes, created_at";

fn row_to_feedback(row: &sqlx::postgres::PgRow) -> RepoResult<Feedback> {
    let raw_type: String = row.try_get("feedback_type").map_err(RepoError::from_sqlx)?;
    let feedback_type = FeedbackType::parse(&raw_type)
        .map_err(|v| RepoError::Validation(format!("unknown feedback.feedback_type '{v}'")))?;

    Ok(Feedback {
        id: row.try_get("id").map_err(RepoError::from_sqlx)?,
        extracted_item_id: row
            .try_get("extracted_item_id")
            .map_err(RepoError::from_sqlx)?,
        feedback_type,
        notes: row.try_get("notes").map_err(RepoError::from_sqlx)?,
        created_at: row.try_get("created_at").map_err(RepoError::from_sqlx)?,
    })
}

/// Postgres implementation.
#[derive(Debug, Clone)]
pub struct PgFeedbackRepository {
    pool: sqlx::PgPool,
}

impl PgFeedbackRepository {
    /// Build a repository from a [`Database`].
    #[must_use]
    pub fn new(database: &Database) -> Self {
        Self {
            pool: database.pool.clone(),
        }
    }
}

#[async_trait]
impl FeedbackRepository for PgFeedbackRepository {
    async fn insert(&self, payload: &NewFeedback) -> RepoResult<Feedback> {
        let sql = format!(
            "INSERT INTO ai_radar.feedback (extracted_item_id, feedback_type, notes) \
             VALUES ($1, $2, $3) RETURNING {SELECT_COLS}"
        );
        let row = sqlx::query(&sql)
            .bind(payload.extracted_item_id)
            .bind(payload.feedback_type.as_str())
            .bind(&payload.notes)
            .fetch_one(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
        row_to_feedback(&row)
    }

    async fn list_for_item(&self, extracted_item_id: Uuid) -> RepoResult<Vec<Feedback>> {
        let sql = format!(
            "SELECT {SELECT_COLS} FROM ai_radar.feedback \
             WHERE extracted_item_id = $1 ORDER BY created_at DESC"
        );
        let rows = sqlx::query(&sql)
            .bind(extracted_item_id)
            .fetch_all(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
        rows.iter().map(row_to_feedback).collect()
    }
}
