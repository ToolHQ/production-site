//! Scoring: deterministic rules (**T-166**) + optional LLM merge (**T-167**).

mod engine;
mod llm;
mod merge;
mod rules;

pub use engine::{decision_from_points, next_step_for, ScoreResult, Scorer, SCORING_VERSION_DETERMINISTIC_V1};
pub use llm::{
    log_llm_cost, merged_to_new_score, LlmScoreOpinion, LlmScorer, LLM_SCORER_PROMPT_V1,
    SCORING_VERSION_MERGED_V1,
};
pub use merge::{MergePolicy, MergedScoreResult};
pub use rules::{Rule, RulePredicate, RULES_V1};
