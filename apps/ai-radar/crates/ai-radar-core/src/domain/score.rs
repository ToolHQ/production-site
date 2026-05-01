//! `scores` table: deterministic + optional LLM-merged scoring output.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Recommendation matching the SQL CHECK in 0002.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Decision {
    /// Adopt now.
    Adopt,
    /// Test in a sandbox / spike.
    Test,
    /// Keep watching.
    Monitor,
    /// Ignore.
    Ignore,
}

impl Decision {
    /// Persisted form.
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            Decision::Adopt => "adopt",
            Decision::Test => "test",
            Decision::Monitor => "monitor",
            Decision::Ignore => "ignore",
        }
    }

    /// Parse the persisted form.
    ///
    /// # Errors
    ///
    /// Returns the offending value when not one of the documented variants.
    pub fn parse(value: &str) -> Result<Self, String> {
        match value {
            "adopt" => Ok(Decision::Adopt),
            "test" => Ok(Decision::Test),
            "monitor" => Ok(Decision::Monitor),
            "ignore" => Ok(Decision::Ignore),
            other => Err(other.to_string()),
        }
    }
}

/// Strongly-typed row from `ai_radar.scores`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Score {
    /// Primary key.
    pub id: Uuid,
    /// FK to `extracted_items.id`.
    pub extracted_item_id: Uuid,
    /// Score in `[0.0, 1.0]` (CHECK in SQL).
    pub score: f32,
    /// Recommendation.
    pub decision: Decision,
    /// Operator-actionable next step.
    pub next_step: Option<String>,
    /// JSON array of reason strings.
    pub reasons_json: serde_json::Value,
    /// JSON array of risk strings.
    pub risks_json: serde_json::Value,
    /// Scoring engine version (e.g. `deterministic-v1`, `merged-llm-v1`).
    pub scoring_version: String,
    /// Free-form metadata (e.g. per-rule contributions).
    pub metadata_json: serde_json::Value,
    /// Row timestamp.
    pub created_at: DateTime<Utc>,
}

/// Insert payload for [`ScoreRepository::insert`].
#[derive(Debug, Clone)]
pub struct NewScore {
    /// FK to `extracted_items.id`.
    pub extracted_item_id: Uuid,
    /// Score in `[0.0, 1.0]`.
    pub score: f32,
    /// Recommendation.
    pub decision: Decision,
    /// Optional next step.
    pub next_step: Option<String>,
    /// Reasons (defaults to `[]`).
    pub reasons_json: Option<serde_json::Value>,
    /// Risks (defaults to `[]`).
    pub risks_json: Option<serde_json::Value>,
    /// Scoring engine version. Required.
    pub scoring_version: String,
    /// Free-form metadata.
    pub metadata_json: Option<serde_json::Value>,
}

impl NewScore {
    /// Validate the payload.
    ///
    /// # Errors
    ///
    /// Returns when score is not finite, out of `[0,1]`, or when
    /// `scoring_version` is blank.
    pub fn validate(&self) -> Result<(), String> {
        if !self.score.is_finite() {
            return Err(format!("score must be finite, got {}", self.score));
        }
        if !(0.0..=1.0).contains(&self.score) {
            return Err(format!("score must be in [0.0, 1.0], got {}", self.score));
        }
        if self.scoring_version.trim().is_empty() {
            return Err("scoring_version must not be empty".into());
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decision_roundtrip() {
        for v in [
            Decision::Adopt,
            Decision::Test,
            Decision::Monitor,
            Decision::Ignore,
        ] {
            assert_eq!(Decision::parse(v.as_str()).unwrap(), v);
        }
    }

    #[test]
    fn score_validation_rejects_out_of_range() {
        let s = NewScore {
            extracted_item_id: Uuid::nil(),
            score: 1.5,
            decision: Decision::Adopt,
            next_step: None,
            reasons_json: None,
            risks_json: None,
            scoring_version: "v1".into(),
            metadata_json: None,
        };
        assert!(s.validate().unwrap_err().contains("[0.0, 1.0]"));
    }

    #[test]
    fn score_validation_rejects_nan() {
        let s = NewScore {
            extracted_item_id: Uuid::nil(),
            score: f32::NAN,
            decision: Decision::Adopt,
            next_step: None,
            reasons_json: None,
            risks_json: None,
            scoring_version: "v1".into(),
            metadata_json: None,
        };
        assert!(s.validate().unwrap_err().contains("finite"));
    }
}
