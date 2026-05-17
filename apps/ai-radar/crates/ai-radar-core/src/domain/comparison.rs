//! `comparisons` table — persisted category matrices (**T-168**).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Stored comparison run.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Comparison {
    /// Primary key.
    pub id: Uuid,
    /// Category label (exact match key for tools).
    pub category: String,
    /// Requested top-N cap.
    pub top_n: i32,
    /// Structured matrix payload.
    pub matrix_json: serde_json::Value,
    /// Rendered Markdown snapshot.
    pub markdown: String,
    /// When the comparison was generated.
    pub generated_at: DateTime<Utc>,
}

/// Insert payload for a comparison row.
#[derive(Debug, Clone)]
pub struct NewComparison {
    /// Category compared.
    pub category: String,
    /// Top-N requested.
    pub top_n: i32,
    /// Structured matrix.
    pub matrix_json: serde_json::Value,
    /// Rendered Markdown.
    pub markdown: String,
}
