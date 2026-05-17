//! Category-level score adjustment from operator feedback (**T-236**).

use serde::{Deserialize, Serialize};

use crate::scorer::{
    decision_from_points, next_step_for, MergePolicy, MergedScoreResult, ScoreResult,
};

/// Aggregated human labels for one category.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CategoryFeedbackStats {
    pub category: String,
    pub total: i64,
    pub negative: i64,
    pub positive: i64,
}

impl CategoryFeedbackStats {
    /// Minimum feedback rows before calibration applies.
    pub const MIN_SAMPLES: i64 = 3;
}

/// Point delta from category feedback mix (−4..=+1).
#[must_use]
pub fn calibration_delta(stats: &CategoryFeedbackStats) -> i32 {
    if stats.total < CategoryFeedbackStats::MIN_SAMPLES {
        return 0;
    }
    let neg_ratio = stats.negative as f64 / stats.total as f64;
    let pos_ratio = stats.positive as f64 / stats.total as f64;
    if neg_ratio >= 0.5 {
        -4
    } else if neg_ratio >= 0.35 {
        -2
    } else if pos_ratio >= 0.5 {
        1
    } else {
        0
    }
}

/// Apply category feedback calibration to a merged score (mutates result).
///
/// Returns `true` when points were adjusted.
#[must_use]
pub fn apply_feedback_calibration(
    merged: &mut MergedScoreResult,
    stats: &CategoryFeedbackStats,
) -> bool {
    let delta = calibration_delta(stats);
    if delta == 0 {
        return false;
    }
    merged.final_points = (merged.final_points + delta).clamp(0, 100);
    merged.decision = decision_from_points(merged.final_points);
    merged.next_step = next_step_for(merged.decision);
    merged.reasons.push(format!(
        "Category feedback calibration ({delta:+} pts; {} negative / {} total labels)",
        stats.negative, stats.total
    ));
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    fn merged_with_points(points: i32) -> MergedScoreResult {
        MergedScoreResult::merge(
            ScoreResult {
                points,
                decision: decision_from_points(points),
                reasons: vec![],
                risks: vec![],
                next_step: next_step_for(decision_from_points(points)),
                applied_rules: vec![],
            },
            None,
            MergePolicy::DeterministicOnly,
        )
    }

    #[test]
    fn penalizes_noisy_category() {
        let mut m = merged_with_points(70);
        let stats = CategoryFeedbackStats {
            category: "devtools".into(),
            total: 10,
            negative: 6,
            positive: 1,
        };
        assert!(apply_feedback_calibration(&mut m, &stats));
        assert_eq!(m.final_points, 66);
    }

    #[test]
    fn skips_small_sample() {
        let mut m = merged_with_points(70);
        let stats = CategoryFeedbackStats {
            category: "x".into(),
            total: 2,
            negative: 2,
            positive: 0,
        };
        assert!(!apply_feedback_calibration(&mut m, &stats));
    }
}
