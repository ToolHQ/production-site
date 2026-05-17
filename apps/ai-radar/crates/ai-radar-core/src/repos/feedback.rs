//! `feedback` repository.

use async_trait::async_trait;
use sqlx::Row;
use uuid::Uuid;

use crate::db::{Database, RepoError, RepoResult};
use crate::curation::feedback_calibration::CategoryFeedbackStats;
use crate::domain::{Decision, Feedback, FeedbackType, NewFeedback};

/// Operations on `feedback`.
#[async_trait]
pub trait FeedbackRepository: Send + Sync {
    /// Append a feedback entry.
    async fn insert(&self, payload: &NewFeedback) -> RepoResult<Feedback>;

    /// Return every feedback for an extracted item, newest first.
    async fn list_for_item(&self, extracted_item_id: Uuid) -> RepoResult<Vec<Feedback>>;

    /// Feedback rows where the label disagrees with the latest score decision.
    async fn list_divergences(&self, limit: i64, offset: i64) -> RepoResult<Vec<FeedbackDivergence>>;

    /// Per-category feedback counts for score calibration (**T-236**).
    async fn list_category_stats(&self) -> RepoResult<Vec<CategoryFeedbackStats>>;
}

/// Human vs scorer mismatch for reporting.
#[derive(Debug, Clone, serde::Serialize)]
pub struct FeedbackDivergence {
    pub feedback: Feedback,
    pub extracted_item_id: Uuid,
    pub tool_name: Option<String>,
    pub category: Option<String>,
    pub decision: Decision,
    pub score: f32,
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

    async fn list_divergences(&self, limit: i64, offset: i64) -> RepoResult<Vec<FeedbackDivergence>> {
        let sql = "\
            SELECT \
                f.id, f.extracted_item_id, f.feedback_type, f.notes, f.created_at, \
                e.tool_name, e.category, \
                s.decision, s.score \
            FROM ai_radar.feedback f \
            JOIN ai_radar.extracted_items e ON e.id = f.extracted_item_id \
            JOIN LATERAL ( \
                SELECT decision, score \
                FROM ai_radar.scores \
                WHERE extracted_item_id = e.id \
                ORDER BY created_at DESC \
                LIMIT 1 \
            ) s ON true \
            WHERE ( \
                (f.feedback_type IN ('rejected', 'low_quality', 'irrelevant', 'wrong_category') \
                 AND s.decision IN ('adopt', 'test')) \
                OR (f.feedback_type = 'adopted' AND s.decision IN ('ignore', 'monitor')) \
            ) \
            ORDER BY f.created_at DESC \
            LIMIT $1 OFFSET $2";

        let rows = sqlx::query(sql)
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;

        rows.iter()
            .map(|row| {
                let feedback = row_to_feedback(row)?;
                let decision_raw: String = row.try_get("decision").map_err(RepoError::from_sqlx)?;
                let decision = Decision::parse(&decision_raw)
                    .map_err(|v| RepoError::Validation(format!("unknown decision '{v}'")))?;
                Ok(FeedbackDivergence {
                    extracted_item_id: feedback.extracted_item_id,
                    tool_name: row.try_get("tool_name").map_err(RepoError::from_sqlx)?,
                    category: row.try_get("category").map_err(RepoError::from_sqlx)?,
                    decision,
                    score: row.try_get("score").map_err(RepoError::from_sqlx)?,
                    feedback,
                })
            })
            .collect()
    }

    async fn list_category_stats(&self) -> RepoResult<Vec<CategoryFeedbackStats>> {
        let rows = sqlx::query(
            "SELECT \
                COALESCE(NULLIF(TRIM(e.category), ''), '(uncategorized)') AS category, \
                COUNT(*)::bigint AS total, \
                COUNT(*) FILTER ( \
                    WHERE f.feedback_type IN ('rejected', 'low_quality', 'irrelevant', 'wrong_category') \
                )::bigint AS negative, \
                COUNT(*) FILTER ( \
                    WHERE f.feedback_type IN ('useful', 'adopted', 'tested') \
                )::bigint AS positive \
             FROM ai_radar.feedback f \
             JOIN ai_radar.extracted_items e ON e.id = f.extracted_item_id \
             GROUP BY 1 \
             HAVING COUNT(*) > 0 \
             ORDER BY total DESC",
        )
        .fetch_all(&self.pool)
        .await
        .map_err(RepoError::from_sqlx)?;

        rows.iter()
            .map(|row| {
                Ok(CategoryFeedbackStats {
                    category: row.try_get("category").map_err(RepoError::from_sqlx)?,
                    total: row.try_get("total").map_err(RepoError::from_sqlx)?,
                    negative: row.try_get("negative").map_err(RepoError::from_sqlx)?,
                    positive: row.try_get("positive").map_err(RepoError::from_sqlx)?,
                })
            })
            .collect()
    }
}
