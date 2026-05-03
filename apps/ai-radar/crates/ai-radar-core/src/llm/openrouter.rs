//! OpenAI-compatible chat completions (`OpenRouter`, `Ollama`, `vLLM`, …).

use std::sync::Arc;
use std::time::Instant;

use async_trait::async_trait;
use reqwest::header::{CONTENT_TYPE, USER_AGENT};
use reqwest::StatusCode;
use serde::Deserialize;
use serde_json::json;

use crate::config::AppConfig;

use super::error::LlmError;
use super::types::{CompletionRequest, CompletionResponse};
use super::LlmProvider;

const OPENROUTER_REFERER: &str = "https://dnor.io";
const OPENROUTER_TITLE: &str = "ai-radar";

/// Live HTTP client targeting an OpenAI-compatible `/chat/completions` endpoint.
#[derive(Debug, Clone)]
pub struct OpenRouterLlmProvider {
    client: reqwest::Client,
    url: String,
    api_key: String,
    model: String,
}

impl OpenRouterLlmProvider {
    /// Build from application config (`LLM_*` must be coherent when `llm_enabled`).
    ///
    /// # Errors
    ///
    /// [`LlmError::Misconfigured`] when the model or API key is missing/blank or the
    /// HTTP client cannot be constructed.
    pub fn try_new(cfg: &AppConfig) -> Result<Self, LlmError> {
        let api_key = cfg
            .llm_api_key
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .ok_or_else(|| {
                LlmError::Misconfigured("LLM_API_KEY is required when LLM_ENABLED=true".into())
            })?
            .to_string();

        let model = cfg
            .llm_model
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .ok_or_else(|| {
                LlmError::Misconfigured("LLM_MODEL is required when LLM_ENABLED=true".into())
            })?
            .to_string();

        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(cfg.llm_timeout_seconds))
            .build()
            .map_err(|e| LlmError::Misconfigured(format!("reqwest client: {e}")))?;

        let base = cfg.llm_base_url.trim_end_matches('/');
        let url = format!("{base}/chat/completions");

        Ok(Self {
            client,
            url,
            api_key,
            model,
        })
    }
}

#[derive(Debug, Deserialize)]
struct ChatCompletionBody {
    choices: Vec<Choice>,
    model: Option<String>,
    usage: Option<Usage>,
}

#[derive(Debug, Deserialize)]
struct Choice {
    message: Message,
}

#[derive(Debug, Deserialize)]
struct Message {
    content: Option<String>,
}

#[derive(Debug, Deserialize)]
struct Usage {
    prompt_tokens: Option<u32>,
    completion_tokens: Option<u32>,
}

fn map_status(status: StatusCode, body: &str) -> LlmError {
    let snippet = body.chars().take(512).collect::<String>();
    match status {
        StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN => {
            LlmError::Auth(format!("HTTP {status}: {snippet}"))
        }
        StatusCode::TOO_MANY_REQUESTS => LlmError::RateLimited(format!("HTTP {status}: {snippet}")),
        s if s.is_server_error() => LlmError::Server(format!("HTTP {status}: {snippet}")),
        other => LlmError::Http(other.as_u16(), snippet),
    }
}

#[async_trait]
impl LlmProvider for OpenRouterLlmProvider {
    async fn complete(&self, req: CompletionRequest) -> Result<CompletionResponse, LlmError> {
        let started = Instant::now();
        let mut body = json!({
            "model": self.model,
            "messages": [
                {"role": "system", "content": req.system},
                {"role": "user", "content": req.user},
            ],
            "temperature": req.temperature,
            "max_tokens": req.max_tokens,
        });
        if req.json_mode {
            if let Some(map) = body.as_object_mut() {
                map.insert(
                    "response_format".to_string(),
                    json!({"type": "json_object"}),
                );
            }
        }

        let response = self
            .client
            .post(&self.url)
            .bearer_auth(&self.api_key)
            .header(CONTENT_TYPE, "application/json")
            .header("HTTP-Referer", OPENROUTER_REFERER)
            .header("X-Title", OPENROUTER_TITLE)
            .header(USER_AGENT, format!("ai-radar/{}", crate::VERSION))
            .json(&body)
            .send()
            .await
            .map_err(|e| {
                if e.is_timeout() {
                    LlmError::Timeout
                } else {
                    LlmError::Server(e.to_string())
                }
            })?;

        let status = response.status();
        let text = response
            .text()
            .await
            .map_err(|e| LlmError::Parse(e.to_string()))?;

        if !status.is_success() {
            return Err(map_status(status, &text));
        }

        let parsed: ChatCompletionBody =
            serde_json::from_str(&text).map_err(|e| LlmError::Parse(e.to_string()))?;
        let content = parsed
            .choices
            .first()
            .and_then(|c| c.message.content.clone())
            .filter(|s| !s.is_empty())
            .ok_or_else(|| LlmError::Parse("missing choices[0].message.content".into()))?;

        let latency_ms = u64::try_from(started.elapsed().as_millis().min(u128::from(u64::MAX)))
            .expect("bounded by u64::MAX");
        Ok(CompletionResponse {
            content,
            prompt_tokens: parsed.usage.as_ref().and_then(|u| u.prompt_tokens),
            completion_tokens: parsed.usage.as_ref().and_then(|u| u.completion_tokens),
            model: parsed.model.unwrap_or_else(|| self.model.clone()),
            latency_ms,
        })
    }
}

/// Wrap concrete provider as trait object.
///
/// # Errors
///
/// Propagates [`OpenRouterLlmProvider::try_new`].
pub fn openrouter_arc(cfg: &AppConfig) -> Result<Arc<dyn LlmProvider>, LlmError> {
    Ok(Arc::new(OpenRouterLlmProvider::try_new(cfg)?))
}
