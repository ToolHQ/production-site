//! Deterministic scorer engine (**T-166**).

use uuid::Uuid;

use crate::domain::{Decision, ExtractedItem, NewScore};

use super::rules::Rule;
use super::rules::RULES_V1;

/// Version string persisted on `scores.scoring_version`.
pub const SCORING_VERSION_DETERMINISTIC_V1: &str = "deterministic-v1";

/// Outcome of [`Scorer::score`] before persistence.
#[derive(Debug, Clone)]
pub struct ScoreResult {
    /// Integer points in `[0, 100]` after clamping (roadmap thresholds apply here).
    pub points: i32,
    /// Mapped recommendation.
    pub decision: Decision,
    /// Human-readable contributions (signed weights + rule id + text).
    pub reasons: Vec<String>,
    /// Short risk tags (subset also implied by negative rules).
    pub risks: Vec<String>,
    /// Operator-facing follow-up.
    pub next_step: String,
    /// Compact audit of matched rules for `metadata_json`.
    pub applied_rules: Vec<serde_json::Value>,
}

impl ScoreResult {
    /// Map integer points to the `[0.0, 1.0]` SQL representation.
    #[must_use]
    #[allow(clippy::cast_precision_loss)] // 0..=100 fits exactly in `f32`
    pub fn normalized_score(&self) -> f32 {
        (self.points.clamp(0, 100) as f32) / 100.0
    }

    /// Build a row for [`crate::repos::ScoreRepository::insert`].
    #[must_use]
    pub fn to_new_score(&self, extracted_item_id: Uuid) -> NewScore {
        NewScore {
            extracted_item_id,
            score: self.normalized_score(),
            decision: self.decision,
            next_step: Some(self.next_step.clone()),
            reasons_json: Some(serde_json::to_value(&self.reasons).unwrap_or(serde_json::json!([]))),
            risks_json: Some(serde_json::to_value(&self.risks).unwrap_or(serde_json::json!([]))),
            scoring_version: SCORING_VERSION_DETERMINISTIC_V1.to_string(),
            metadata_json: Some(serde_json::json!({
                "points": self.points,
                "rules_applied": self.applied_rules,
            })),
        }
    }
}

/// Rule-driven deterministic scorer.
#[derive(Debug, Clone)]
pub struct Scorer {
    rules: &'static [Rule],
}

impl Scorer {
    /// Ruleset `deterministic-v1`.
    #[must_use]
    pub fn v1() -> Self {
        Self { rules: RULES_V1 }
    }

    /// Build with an explicit rule slice (tests).
    #[must_use]
    pub fn with_rules(rules: &'static [Rule]) -> Self {
        Self { rules }
    }

    /// Evaluate all rules, clamp to `[0, 100]`, map thresholds, and build reasons/risks.
    #[must_use]
    pub fn score(&self, item: &ExtractedItem) -> ScoreResult {
        // Neutral prior so mixed signals land near “monitor” without rules.
        let mut points: i32 = 50;
        let mut reasons = Vec::new();
        let mut risks = Vec::new();
        let mut applied_rules = Vec::new();

        for r in self.rules {
            if (r.predicate)(item) {
                points += r.weight;
                reasons.push(format!("{:+} [{}] {}", r.weight, r.id, r.reason));
                if let Some(risk) = r.risk {
                    risks.push(risk.to_string());
                }
                applied_rules.push(serde_json::json!({
                    "id": r.id,
                    "weight": r.weight,
                }));
            }
        }

        points = points.clamp(0, 100);
        let decision = decision_from_points(points);
        let next_step = next_step_for(decision);

        ScoreResult {
            points,
            decision,
            reasons,
            risks,
            next_step,
            applied_rules,
        }
    }
}

fn decision_from_points(p: i32) -> Decision {
    match p {
        x if x >= 80 => Decision::Adopt,
        x if x >= 60 => Decision::Test,
        x if x >= 35 => Decision::Monitor,
        _ => Decision::Ignore,
    }
}

fn next_step_for(d: Decision) -> String {
    match d {
        Decision::Adopt => {
            "Promote to team standard; track adoption metrics and owner.".to_string()
        }
        Decision::Test => "Run a time-boxed spike in a sandbox cluster before wide rollout.".to_string(),
        Decision::Monitor => {
            "No immediate action — revisit next digest cycle unless signals change.".to_string()
        }
        Decision::Ignore => "Archive; do not spend further review time unless new evidence appears."
            .to_string(),
    }
}
