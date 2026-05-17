//! Explorer list rows — extracted items joined with their latest score.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::Decision;

/// GitHub adoption block surfaced on explorer rows (**T-235**).
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AdoptionSummary {
    pub stars_tier: Option<String>,
    pub activity_tier: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stars: Option<i64>,
}

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
    /// Present when `metadata_json.adoption` exists (**T-233**).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub adoption: Option<AdoptionSummary>,
    /// `metadata_json.quality_warn` from extract gate.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quality_warn: Option<bool>,
}
