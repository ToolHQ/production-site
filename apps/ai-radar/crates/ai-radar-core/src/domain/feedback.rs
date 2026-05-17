//! `feedback` table: human feedback on extracted items.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::Decision;

/// One of the nine documented feedback labels.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FeedbackType {
    /// Useful overall.
    Useful,
    /// Off-topic / not relevant.
    Irrelevant,
    /// Already known / duplicate.
    Duplicate,
    /// Low quality (broken, vapor, spam).
    LowQuality,
    /// Categorized incorrectly.
    WrongCategory,
    /// Adopted in production.
    Adopted,
    /// Tested in a spike.
    Tested,
    /// Currently monitoring.
    Monitoring,
    /// Rejected (do not surface again).
    Rejected,
}

impl FeedbackType {
    /// Persisted form.
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            FeedbackType::Useful => "useful",
            FeedbackType::Irrelevant => "irrelevant",
            FeedbackType::Duplicate => "duplicate",
            FeedbackType::LowQuality => "low_quality",
            FeedbackType::WrongCategory => "wrong_category",
            FeedbackType::Adopted => "adopted",
            FeedbackType::Tested => "tested",
            FeedbackType::Monitoring => "monitoring",
            FeedbackType::Rejected => "rejected",
        }
    }

    /// Parse the persisted form.
    ///
    /// # Errors
    ///
    /// Returns the offending value when not one of the documented variants.
    pub fn parse(value: &str) -> Result<Self, String> {
        match value {
            "useful" => Ok(FeedbackType::Useful),
            "irrelevant" => Ok(FeedbackType::Irrelevant),
            "duplicate" => Ok(FeedbackType::Duplicate),
            "low_quality" => Ok(FeedbackType::LowQuality),
            "wrong_category" => Ok(FeedbackType::WrongCategory),
            "adopted" => Ok(FeedbackType::Adopted),
            "tested" => Ok(FeedbackType::Tested),
            "monitoring" => Ok(FeedbackType::Monitoring),
            "rejected" => Ok(FeedbackType::Rejected),
            other => Err(other.to_string()),
        }
    }
}

/// Strongly-typed row from `ai_radar.feedback`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Feedback {
    /// Primary key.
    pub id: Uuid,
    /// FK to `extracted_items.id`.
    pub extracted_item_id: Uuid,
    /// Feedback label.
    pub feedback_type: FeedbackType,
    /// Optional free-text notes.
    pub notes: Option<String>,
    /// Row timestamp.
    pub created_at: DateTime<Utc>,
}

/// Whether human feedback disagrees with the latest automated decision.
#[must_use]
pub fn feedback_diverges_from_decision(feedback: FeedbackType, decision: Decision) -> bool {
    match feedback {
        FeedbackType::Rejected | FeedbackType::LowQuality | FeedbackType::Irrelevant
        | FeedbackType::WrongCategory => {
            matches!(decision, Decision::Adopt | Decision::Test)
        }
        FeedbackType::Adopted => matches!(decision, Decision::Ignore | Decision::Monitor),
        FeedbackType::Useful | FeedbackType::Duplicate | FeedbackType::Tested
        | FeedbackType::Monitoring => false,
    }
}

/// Insert payload.
#[derive(Debug, Clone)]
pub struct NewFeedback {
    /// FK to `extracted_items.id`.
    pub extracted_item_id: Uuid,
    /// Feedback label.
    pub feedback_type: FeedbackType,
    /// Optional notes.
    pub notes: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn divergence_detects_reject_on_adopt() {
        assert!(feedback_diverges_from_decision(
            FeedbackType::Rejected,
            Decision::Adopt
        ));
        assert!(!feedback_diverges_from_decision(
            FeedbackType::Useful,
            Decision::Adopt
        ));
    }

    #[test]
    fn feedback_type_roundtrip_all_nine() {
        for v in [
            FeedbackType::Useful,
            FeedbackType::Irrelevant,
            FeedbackType::Duplicate,
            FeedbackType::LowQuality,
            FeedbackType::WrongCategory,
            FeedbackType::Adopted,
            FeedbackType::Tested,
            FeedbackType::Monitoring,
            FeedbackType::Rejected,
        ] {
            assert_eq!(FeedbackType::parse(v.as_str()).unwrap(), v);
        }
    }
}
