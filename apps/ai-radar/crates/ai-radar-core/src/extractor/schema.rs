//! LLM JSON payload deserialized into structured fields (T-165).

use serde::Deserialize;
use serde_json::Value;
use uuid::Uuid;

use crate::domain::{Maturity, NewExtractedItem, RiskLevel};

/// Fields returned by the extractor model (`EXTRACTOR_PROMPT_V1`).
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct ExtractedFields {
    /// Human-visible title of the item or tool.
    pub title: Option<String>,
    /// Canonical tool or product name.
    pub tool_name: Option<String>,
    /// Category label (free text).
    pub category: Option<String>,
    /// Problem statement.
    pub problem_solved: Option<String>,
    /// Target audience (free text).
    pub target_users: Option<String>,
    /// How it fits common stacks / infra.
    pub stack_fit: Option<String>,
    /// Whether it can be self-hosted.
    pub self_hosted: Option<bool>,
    /// SaaS-only flag.
    pub saas_only: Option<bool>,
    /// SPDX or short license string.
    pub license: Option<String>,
    /// Maturity string matching SQL CHECK (`snake_case` values).
    pub maturity: Option<String>,
    /// Risk string: low / medium / high.
    pub risk_level: Option<String>,
    /// Short summary.
    pub summary: Option<String>,
    /// Bullet points (array or string from some models).
    #[serde(default)]
    pub key_points: Option<Value>,
    /// Suggested next action for operators.
    pub recommended_action: Option<String>,
}

impl ExtractedFields {
    /// Map into a DB insert row plus merged `metadata_json` for fields without dedicated columns.
    #[must_use]
    pub fn into_new_extracted_item(
        self,
        raw_item_id: Uuid,
        extractor: &str,
        extractor_prompt_version: &str,
        last_llm: &crate::llm::CompletionResponse,
    ) -> NewExtractedItem {
        let maturity = self
            .maturity
            .as_deref()
            .and_then(|s| Maturity::parse(s.trim()).ok());
        let risk_level = self
            .risk_level
            .as_deref()
            .and_then(|s| RiskLevel::parse(s.trim()).ok());

        let llm_meta = serde_json::json!({
            "title": self.title.clone(),
            "target_users": self.target_users.clone(),
            "key_points": self.key_points.clone(),
            "recommended_action": self.recommended_action.clone(),
        });
        let mut extra = serde_json::json!({
            "extractor_prompt_version": extractor_prompt_version,
            "llm": llm_meta,
            "llm_last_response": {
                "model": &last_llm.model,
                "latency_ms": last_llm.latency_ms,
                "prompt_tokens": last_llm.prompt_tokens,
                "completion_tokens": last_llm.completion_tokens,
            },
        });
        if let Some(obj) = extra.get_mut("llm").and_then(|v| v.as_object_mut()) {
            obj.retain(|_, v| !v.is_null());
        }

        NewExtractedItem {
            raw_item_id,
            version: None,
            extractor: extractor.to_string(),
            tool_name: self.tool_name,
            category: self.category,
            summary: self.summary,
            problem_solved: self.problem_solved,
            self_hosted: self.self_hosted,
            saas_only: self.saas_only,
            license: self.license,
            maturity,
            risk_level,
            stack_fit: self.stack_fit,
            metadata_json: Some(extra),
        }
    }
}
