//! Merge deterministic and optional LLM opinions (**T-167**).

use crate::domain::Decision;

use super::engine::{decision_from_points, next_step_for, ScoreResult};
use super::llm::LlmScoreOpinion;

/// How to combine deterministic rules with an LLM opinion.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum MergePolicy {
    /// Ignore any LLM output.
    DeterministicOnly,
    /// Weighted average of integer points in `[0, 100]`.
    Weighted {
        /// Weight for deterministic points (default `0.7`).
        deterministic: f32,
        /// Weight for LLM points (default `0.3`).
        llm: f32,
    },
}

impl MergePolicy {
    /// Build from config flags and weights (normalizes when sum &gt; 0).
    #[must_use]
    pub fn from_config(llm_scoring_enabled: bool, det_w: f32, llm_w: f32) -> Self {
        if !llm_scoring_enabled {
            return Self::DeterministicOnly;
        }
        let sum = det_w + llm_w;
        if sum <= f32::EPSILON {
            return Self::DeterministicOnly;
        }
        Self::Weighted {
            deterministic: det_w / sum,
            llm: llm_w / sum,
        }
    }

    /// Final integer points after merge.
    #[must_use]
    pub fn merge_points(&self, deterministic: i32, llm: Option<i32>) -> i32 {
        match self {
            Self::DeterministicOnly => deterministic.clamp(0, 100),
            Self::Weighted {
                deterministic: dw,
                llm: lw,
            } => {
                let Some(lp) = llm else {
                    return deterministic.clamp(0, 100);
                };
                let merged = (deterministic.clamp(0, 100) as f32) * dw
                    + (lp.clamp(0, 100) as f32) * lw;
                merged.round().clamp(0.0, 100.0) as i32
            }
        }
    }
}

/// Merged scoring outcome ready for persistence.
#[derive(Debug, Clone)]
pub struct MergedScoreResult {
    /// Deterministic engine output (always computed).
    pub deterministic: ScoreResult,
    /// Optional LLM opinion.
    pub llm: Option<LlmScoreOpinion>,
    /// Policy used for the final score.
    pub policy: MergePolicy,
    /// Final integer points.
    pub final_points: i32,
    /// Final recommendation.
    pub decision: Decision,
    /// Operator next step from final decision.
    pub next_step: String,
    /// Combined reasons (deterministic + optional LLM).
    pub reasons: Vec<String>,
    /// Combined risks.
    pub risks: Vec<String>,
}

impl MergedScoreResult {
    /// Merge deterministic output with an optional LLM opinion.
    #[must_use]
    pub fn merge(
        deterministic: ScoreResult,
        llm: Option<LlmScoreOpinion>,
        policy: MergePolicy,
    ) -> Self {
        let llm_points = llm.as_ref().map(|o| o.points);
        let final_points = policy.merge_points(deterministic.points, llm_points);
        let decision = decision_from_points(final_points);
        let next_step = next_step_for(decision);

        let mut reasons = deterministic.reasons.clone();
        if let Some(op) = &llm {
            for r in &op.reasons {
                reasons.push(format!("[llm] {r}"));
            }
        }
        let mut risks = deterministic.risks.clone();
        if let Some(op) = &llm {
            for r in &op.risks {
                if !risks.contains(r) {
                    risks.push(r.clone());
                }
            }
        }

        Self {
            deterministic,
            llm,
            policy,
            final_points,
            decision,
            next_step,
            reasons,
            risks,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::Decision;

    fn sample_det(points: i32) -> ScoreResult {
        ScoreResult {
            points,
            decision: decision_from_points(points),
            reasons: vec!["+10 [r1] rule".into()],
            risks: vec![],
            next_step: next_step_for(decision_from_points(points)),
            applied_rules: vec![],
        }
    }

    #[test]
    fn weighted_default_blend() {
        let det = sample_det(80);
        let llm = LlmScoreOpinion {
            points: 40,
            reasons: vec!["weak docs".into()],
            risks: vec![],
        };
        let policy = MergePolicy::Weighted {
            deterministic: 0.7,
            llm: 0.3,
        };
        let merged = MergedScoreResult::merge(det, Some(llm), policy);
        assert_eq!(merged.final_points, 68); // 80*0.7 + 40*0.3
        assert_eq!(merged.decision, Decision::Test);
    }

    #[test]
    fn deterministic_only_ignores_llm() {
        let det = sample_det(90);
        let llm = LlmScoreOpinion {
            points: 10,
            reasons: vec![],
            risks: vec![],
        };
        let merged = MergedScoreResult::merge(det, Some(llm), MergePolicy::DeterministicOnly);
        assert_eq!(merged.final_points, 90);
        assert_eq!(merged.decision, Decision::Adopt);
    }
}
