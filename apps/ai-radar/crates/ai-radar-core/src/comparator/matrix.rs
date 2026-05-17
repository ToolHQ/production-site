//! Comparison matrix types (**T-168**).

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::criteria::CriteriaScores;
use crate::domain::Decision;

/// One row in a category comparison.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ComparisonRow {
    /// Tool label.
    pub tool_name: String,
    /// Source extracted item id.
    pub extracted_item_id: Uuid,
    /// Latest normalized score `[0,1]`.
    pub overall_score: f32,
    /// Latest decision.
    pub decision: Decision,
    /// Per-criterion 0–3 scores.
    pub criteria: CriteriaScores,
}

/// Full matrix for a single category.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ComparisonMatrix {
    /// Category key (all rows share this exact label).
    pub category: String,
    /// Requested cap.
    pub top_n: usize,
    /// Ranked tools (may be fewer than `top_n` when data is sparse).
    pub rows: Vec<ComparisonRow>,
}

impl ComparisonMatrix {
    /// Sum of criteria as a quick tie-breaker helper.
    #[must_use]
    pub fn criteria_total(row: &ComparisonRow) -> u16 {
        let c = &row.criteria;
        u16::from(c.self_hosted)
            + u16::from(c.k8s_friendly)
            + u16::from(c.license_clarity)
            + u16::from(c.maturity)
            + u16::from(c.last_activity)
            + u16::from(c.doc_quality)
    }
}
