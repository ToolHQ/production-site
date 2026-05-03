//! Deterministic scoring (`deterministic-v1`) — **T-166**.

mod engine;
mod rules;

pub use engine::{ScoreResult, Scorer, SCORING_VERSION_DETERMINISTIC_V1};
pub use rules::{Rule, RulePredicate, RULES_V1};
