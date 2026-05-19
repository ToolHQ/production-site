//! OpenRouter model catalog types (**T-270**).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Provider slug for catalog sync (extensible later).
pub const PROVIDER_OPENROUTER: &str = "openrouter";

/// Diff event kinds persisted in `model_catalog_events`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModelCatalogEventType {
    /// New model id in catalog.
    ModelAdded,
    /// Model id dropped from catalog.
    ModelRemoved,
    /// Prompt or completion price changed.
    PriceChange,
}

impl ModelCatalogEventType {
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            ModelCatalogEventType::ModelAdded => "model_added",
            ModelCatalogEventType::ModelRemoved => "model_removed",
            ModelCatalogEventType::PriceChange => "price_change",
        }
    }
}

/// Normalized model row from OpenRouter `/models`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModelCatalogEntry {
    pub model_id: String,
    pub model_name: Option<String>,
    pub prompt_price: Option<String>,
    pub completion_price: Option<String>,
}

/// One diff to persist.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModelCatalogDiff {
    pub model_id: String,
    pub event_type: ModelCatalogEventType,
    pub prompt_price: Option<String>,
    pub completion_price: Option<String>,
    pub previous_prompt_price: Option<String>,
    pub previous_completion_price: Option<String>,
}

/// Summary of one sync run.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelCatalogRunSummary {
    pub run_id: Uuid,
    pub provider: String,
    pub model_count: i32,
    pub events_count: i32,
    pub collected_at: DateTime<Utc>,
}

/// Event row for API responses.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelCatalogEventRow {
    pub id: Uuid,
    pub run_id: Uuid,
    pub model_id: String,
    pub event_type: String,
    pub prompt_price: Option<String>,
    pub completion_price: Option<String>,
    pub previous_prompt_price: Option<String>,
    pub previous_completion_price: Option<String>,
    pub created_at: DateTime<Utc>,
}
