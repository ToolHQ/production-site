//! `extracted_items` table: structured output of the extractor stage.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Maturity grade matching the SQL CHECK in 0002.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Maturity {
    /// Pre-alpha / experimental.
    Experimental,
    /// Beta / not yet stable.
    Beta,
    /// Stable, production-recommended.
    Stable,
    /// Mature, broadly adopted.
    Mature,
    /// Deprecated.
    Deprecated,
}

impl Maturity {
    /// Persisted form.
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            Maturity::Experimental => "experimental",
            Maturity::Beta => "beta",
            Maturity::Stable => "stable",
            Maturity::Mature => "mature",
            Maturity::Deprecated => "deprecated",
        }
    }

    /// Parse the persisted form.
    ///
    /// # Errors
    ///
    /// Returns the offending value when not one of the documented variants.
    pub fn parse(value: &str) -> Result<Self, String> {
        match value {
            "experimental" => Ok(Maturity::Experimental),
            "beta" => Ok(Maturity::Beta),
            "stable" => Ok(Maturity::Stable),
            "mature" => Ok(Maturity::Mature),
            "deprecated" => Ok(Maturity::Deprecated),
            other => Err(other.to_string()),
        }
    }
}

/// Risk grade matching the SQL CHECK in 0002.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RiskLevel {
    /// Low risk.
    Low,
    /// Medium risk.
    Medium,
    /// High risk.
    High,
}

impl RiskLevel {
    /// Persisted form.
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            RiskLevel::Low => "low",
            RiskLevel::Medium => "medium",
            RiskLevel::High => "high",
        }
    }

    /// Parse the persisted form.
    ///
    /// # Errors
    ///
    /// Returns the offending value when not one of the documented variants.
    pub fn parse(value: &str) -> Result<Self, String> {
        match value {
            "low" => Ok(RiskLevel::Low),
            "medium" => Ok(RiskLevel::Medium),
            "high" => Ok(RiskLevel::High),
            other => Err(other.to_string()),
        }
    }
}

/// Strongly-typed row from `ai_radar.extracted_items`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtractedItem {
    /// Primary key.
    pub id: Uuid,
    /// FK to `raw_items.id`.
    pub raw_item_id: Uuid,
    /// Reprocess version, ≥1.
    pub version: i32,
    /// Extractor identifier (e.g. `deterministic-v1`, `llm-v2`).
    pub extractor: String,
    /// Tool name extracted from the content.
    pub tool_name: Option<String>,
    /// Operator-friendly category.
    pub category: Option<String>,
    /// One-line summary.
    pub summary: Option<String>,
    /// Problem the tool solves.
    pub problem_solved: Option<String>,
    /// Whether the tool can be self-hosted.
    pub self_hosted: Option<bool>,
    /// Whether the tool is SaaS-only.
    pub saas_only: Option<bool>,
    /// License (e.g. `MIT`, `Apache-2.0`, `proprietary`).
    pub license: Option<String>,
    /// Maturity grade.
    pub maturity: Option<Maturity>,
    /// Risk grade.
    pub risk_level: Option<RiskLevel>,
    /// Stack fit notes.
    pub stack_fit: Option<String>,
    /// Free-form metadata.
    pub metadata_json: serde_json::Value,
    /// Row timestamp.
    pub created_at: DateTime<Utc>,
}

/// Insert payload for [`ExtractedItemRepository::insert`].
#[derive(Debug, Clone, Default)]
pub struct NewExtractedItem {
    /// FK to `raw_items.id`.
    pub raw_item_id: Uuid,
    /// Reprocess version. The repository defaults to the next free
    /// version when `None`.
    pub version: Option<i32>,
    /// Extractor identifier.
    pub extractor: String,
    /// Tool name.
    pub tool_name: Option<String>,
    /// Category.
    pub category: Option<String>,
    /// Summary.
    pub summary: Option<String>,
    /// Problem solved.
    pub problem_solved: Option<String>,
    /// Self-hosted flag.
    pub self_hosted: Option<bool>,
    /// SaaS-only flag.
    pub saas_only: Option<bool>,
    /// License.
    pub license: Option<String>,
    /// Maturity grade.
    pub maturity: Option<Maturity>,
    /// Risk grade.
    pub risk_level: Option<RiskLevel>,
    /// Stack fit notes.
    pub stack_fit: Option<String>,
    /// Free-form metadata.
    pub metadata_json: Option<serde_json::Value>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maturity_roundtrip() {
        for v in [
            Maturity::Experimental,
            Maturity::Beta,
            Maturity::Stable,
            Maturity::Mature,
            Maturity::Deprecated,
        ] {
            assert_eq!(Maturity::parse(v.as_str()).unwrap(), v);
        }
    }

    #[test]
    fn risk_level_roundtrip() {
        for v in [RiskLevel::Low, RiskLevel::Medium, RiskLevel::High] {
            assert_eq!(RiskLevel::parse(v.as_str()).unwrap(), v);
        }
    }
}
