//! Explorer list rows — extracted items joined with their latest score.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::Decision;

/// One row for `GET /items` (latest score per extracted item).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScoredItemSummary {
    /// `extracted_items.id`
    pub extracted_item_id: Uuid,
    pub tool_name: Option<String>,
    pub category: Option<String>,
    pub summary: Option<String>,
    pub score: f32,
    pub decision: Decision,
    pub scored_at: DateTime<Utc>,
    pub extracted_at: DateTime<Utc>,
}
