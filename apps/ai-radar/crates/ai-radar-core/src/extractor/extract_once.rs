//! Two-attempt LLM round-trip for one raw item body (T-165).

use std::sync::Arc;

use serde_json::json;

use crate::domain::RawItem;
use crate::llm::{CompletionRequest, LlmError, LlmProvider};
use crate::util::limits::MAX_EXTRACT_INPUT_CHARS;

use super::parse::parse_extracted_fields;
use super::prompt::EXTRACTOR_PROMPT_V1;
use super::schema::ExtractedFields;

const CORRECTIVE_USER: &str = "Your previous reply was not valid JSON for the agreed schema. Output ONLY one JSON object. No markdown, no code fences, no commentary before or after the object.\n\nParse error:\n";

/// Build the primary user message (URL, title, truncated body).
#[must_use]
pub fn build_primary_user_message(raw: &RawItem) -> String {
    let body: String = raw
        .raw_content
        .chars()
        .take(MAX_EXTRACT_INPUT_CHARS)
        .collect();
    format!(
        "url: {}\ntitle: {}\nexternal_id: {}\n\nbody:\n{}",
        raw.url,
        raw.title.as_deref().unwrap_or(""),
        raw.external_id.as_deref().unwrap_or(""),
        body
    )
}

/// Call the LLM up to twice (corrective second prompt) and return parsed fields + last response.
///
/// Pushes one [`audit_entry`] into `audits` for each finished HTTP round-trip (ok or transport error).
///
/// # Errors
///
/// Returns [`LlmError`] from the LLM on the first transport/auth failure, or [`LlmError::Parse`]
/// when the second JSON parse still fails.
pub async fn llm_extract_with_retry(
    llm: &Arc<dyn LlmProvider>,
    raw: &RawItem,
    audits: &mut Vec<serde_json::Value>,
) -> Result<(ExtractedFields, crate::llm::CompletionResponse), LlmError> {
    let primary = build_primary_user_message(raw);
    let mut last_parse_err = String::new();
    let mut last_completion: Option<crate::llm::CompletionResponse> = None;

    for attempt in 1_u32..=2 {
        let user = if attempt == 1 {
            primary.clone()
        } else {
            format!(
                "{CORRECTIVE_USER}{err}\n\nPrevious output (truncated):\n{snippet}\n\nRepeat with JSON only.",
                err = last_parse_err,
                snippet = last_completion
                    .as_ref()
                    .map(|c| c.content.chars().take(1_200).collect::<String>())
                    .unwrap_or_default()
            )
        };

        let req = CompletionRequest {
            system: EXTRACTOR_PROMPT_V1.to_string(),
            user,
            max_tokens: 4_096,
            temperature: 0.1,
            json_mode: true,
        };

        match llm.complete(req).await {
            Ok(resp) => {
                let est = crate::llm::approx_cost_usd(
                    &resp.model,
                    resp.prompt_tokens,
                    resp.completion_tokens,
                );
                tracing::info!(
                    attempt,
                    raw_item_id = %raw.id,
                    model = %resp.model,
                    latency_ms = resp.latency_ms,
                    prompt_tokens = ?resp.prompt_tokens,
                    completion_tokens = ?resp.completion_tokens,
                    llm.cost_estimate_usd = est,
                    "extract llm completion"
                );

                match parse_extracted_fields(&resp.content) {
                    Ok(fields) => {
                        audits.push(audit_entry(
                            attempt,
                            "success",
                            "parsed JSON",
                            Some(resp.latency_ms),
                        ));
                        return Ok((fields, resp));
                    }
                    Err(parse_err) => {
                        audits.push(audit_entry(
                            attempt,
                            "parse_error",
                            &parse_err,
                            Some(resp.latency_ms),
                        ));
                        last_parse_err = parse_err;
                        last_completion = Some(resp);
                        if attempt == 2 {
                            return Err(LlmError::Parse(
                                "invalid JSON after corrective attempt".into(),
                            ));
                        }
                    }
                }
            }
            Err(e) => {
                audits.push(audit_entry(attempt, "llm_error", e.to_string(), None));
                return Err(e);
            }
        }
    }

    Err(LlmError::Parse(
        "extractor internal: no attempts executed".into(),
    ))
}

/// Append a structured audit row to `raw_items.metadata_json.extract_attempts` via repository.
#[must_use]
pub fn audit_entry(
    attempt: u32,
    kind: &str,
    detail: impl Into<String>,
    latency_ms: Option<u64>,
) -> serde_json::Value {
    json!({
        "attempt": attempt,
        "kind": kind,
        "detail": detail.into(),
        "at": chrono::Utc::now().to_rfc3339(),
        "latency_ms": latency_ms,
    })
}
