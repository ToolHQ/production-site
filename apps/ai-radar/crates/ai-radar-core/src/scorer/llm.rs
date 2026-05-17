//! Optional LLM scoring opinion (**T-167**).

use serde::Deserialize;
use uuid::Uuid;

use crate::domain::ExtractedItem;
use crate::llm::approx_cost_usd;
use crate::llm::{CompletionRequest, CompletionResponse, LlmError, LlmProvider};

/// Persisted when LLM scoring contributed to a row.
pub const SCORING_VERSION_MERGED_V1: &str = "merged-v1";

/// System prompt for the LLM scorer (v1).
pub const LLM_SCORER_PROMPT_V1: &str = r"You are an AI tooling curator scoring assistant.
Use ONLY the structured item fields provided. Do not invent facts, URLs, or capabilities.
Respond with a single JSON object (no markdown fences) containing:
- score: integer 0-100 (higher = stronger adopt signal for our Kubernetes-first, self-hosted bias)
- reasons: array of short strings explaining the score
- risks: array of short risk tags (may be empty)
Anchor strictly to the supplied content.";

/// Parsed LLM scoring opinion.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LlmScoreOpinion {
    /// Integer score in `[0, 100]`.
    pub points: i32,
    /// Human-readable reasons.
    pub reasons: Vec<String>,
    /// Risk tags.
    pub risks: Vec<String>,
}

/// LLM-backed scorer (stateless; uses injected [`LlmProvider`]).
#[derive(Debug, Clone, Default)]
pub struct LlmScorer;

impl LlmScorer {
    /// Request an LLM opinion for `item`.
    ///
    /// # Errors
    ///
    /// Returns [`LlmError`] on transport, disabled provider, or JSON parse failures.
    pub async fn evaluate(
        &self,
        llm: &dyn LlmProvider,
        item: &ExtractedItem,
    ) -> Result<(LlmScoreOpinion, CompletionResponse), LlmError> {
        let user = format_item_payload(item);
        let req = CompletionRequest {
            system: LLM_SCORER_PROMPT_V1.to_string(),
            user,
            max_tokens: 512,
            temperature: 0.1,
            json_mode: true,
        };
        let resp = llm.complete(req).await?;
        let opinion = parse_opinion_json(&resp.content)?;
        Ok((opinion, resp))
    }
}

#[derive(Debug, Deserialize)]
struct LlmScoreJson {
    score: i32,
    #[serde(default)]
    reasons: Vec<String>,
    #[serde(default)]
    risks: Vec<String>,
}

fn parse_opinion_json(raw: &str) -> Result<LlmScoreOpinion, LlmError> {
    let trimmed = raw.trim();
    let value: LlmScoreJson = serde_json::from_str(trimmed).map_err(|e| {
        LlmError::Parse(format!("llm scorer json: {e}; body={}", truncate(trimmed, 200)))
    })?;
    Ok(LlmScoreOpinion {
        points: value.score.clamp(0, 100),
        reasons: value.reasons,
        risks: value.risks,
    })
}

fn truncate(s: &str, max: usize) -> String {
    if s.len() <= max {
        return s.to_string();
    }
    let mut end = max;
    while end > 0 && !s.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}…", &s[..end])
}

fn format_item_payload(item: &ExtractedItem) -> String {
    serde_json::json!({
        "tool_name": item.tool_name,
        "category": item.category,
        "summary": item.summary,
        "problem_solved": item.problem_solved,
        "self_hosted": item.self_hosted,
        "saas_only": item.saas_only,
        "license": item.license,
        "maturity": item.maturity.map(|m| m.as_str()),
        "risk_level": item.risk_level.map(|r| r.as_str()),
        "stack_fit": item.stack_fit,
        "metadata_json": item.metadata_json,
    })
    .to_string()
}

/// Build audit metadata and [`crate::domain::NewScore`] for a merged result.
#[must_use]
pub fn merged_to_new_score(
    merged: &super::merge::MergedScoreResult,
    extracted_item_id: Uuid,
    llm_model: Option<&str>,
    llm_cost_usd: Option<f64>,
) -> crate::domain::NewScore {
    use super::engine::SCORING_VERSION_DETERMINISTIC_V1;

    let scoring_version = match merged.policy {
        super::merge::MergePolicy::DeterministicOnly => SCORING_VERSION_DETERMINISTIC_V1.to_string(),
        super::merge::MergePolicy::Weighted { .. } if merged.llm.is_some() => {
            SCORING_VERSION_MERGED_V1.to_string()
        }
        super::merge::MergePolicy::Weighted { .. } => SCORING_VERSION_DETERMINISTIC_V1.to_string(),
    };

    let policy_label = match merged.policy {
        super::merge::MergePolicy::DeterministicOnly => "deterministic_only".to_string(),
        super::merge::MergePolicy::Weighted {
            deterministic,
            llm,
        } => format!("weighted:{deterministic:.2}:{llm:.2}"),
    };

    let normalized = (merged.final_points.clamp(0, 100) as f32) / 100.0;

    crate::domain::NewScore {
        extracted_item_id,
        score: normalized,
        decision: merged.decision,
        next_step: Some(merged.next_step.clone()),
        reasons_json: Some(
            serde_json::to_value(&merged.reasons).unwrap_or(serde_json::json!([])),
        ),
        risks_json: Some(serde_json::to_value(&merged.risks).unwrap_or(serde_json::json!([]))),
        scoring_version,
        metadata_json: Some(serde_json::json!({
            "points": merged.final_points,
            "deterministic_score": merged.deterministic.points,
            "llm_score": merged.llm.as_ref().map(|o| o.points),
            "merge_policy": policy_label,
            "llm_model": llm_model,
            "llm_cost_usd": llm_cost_usd,
            "rules_applied": merged.deterministic.applied_rules,
        })),
    }
}

/// Log approximate LLM cost for a scorer completion.
pub fn log_llm_cost(model: &str, resp: &CompletionResponse) {
    let usd = approx_cost_usd(model, resp.prompt_tokens, resp.completion_tokens);
    tracing::info!(
        model = %model,
        prompt_tokens = ?resp.prompt_tokens,
        completion_tokens = ?resp.completion_tokens,
        latency_ms = resp.latency_ms,
        approx_cost_usd = usd,
        "llm scorer completion"
    );
}
