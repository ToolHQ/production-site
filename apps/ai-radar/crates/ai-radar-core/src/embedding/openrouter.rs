//! OpenAI-compatible `/embeddings` client (**T-247**).

use async_trait::async_trait;
use reqwest::header::{CONTENT_TYPE, USER_AGENT};
use serde::Deserialize;
use serde_json::json;

use crate::config::AppConfig;

use super::error::EmbeddingError;
use super::types::{EmbedRequest, EmbedResponse};
use super::EmbeddingProvider;

const OPENROUTER_REFERER: &str = "https://dnor.io";
const OPENROUTER_TITLE: &str = "ai-radar";

/// HTTP client for `POST {base}/embeddings`.
#[derive(Debug, Clone)]
pub struct OpenRouterEmbeddingProvider {
    client: reqwest::Client,
    url: String,
    api_key: String,
    model: String,
}

impl OpenRouterEmbeddingProvider {
    /// Build when `embeddings_enabled` and secrets are present.
    ///
    /// # Errors
    ///
    /// [`EmbeddingError::Misconfigured`] on missing model/key or client build failure.
    pub fn try_new(cfg: &AppConfig) -> Result<Self, EmbeddingError> {
        let api_key = cfg
            .llm_api_key
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .ok_or_else(|| {
                EmbeddingError::Misconfigured(
                    "LLM_API_KEY is required when EMBEDDINGS_ENABLED=true".into(),
                )
            })?
            .to_string();

        let model = cfg
            .embedding_model
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .ok_or_else(|| {
                EmbeddingError::Misconfigured(
                    "EMBEDDING_MODEL is required when EMBEDDINGS_ENABLED=true".into(),
                )
            })?
            .to_string();

        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(cfg.llm_timeout_seconds))
            .build()
            .map_err(|e| EmbeddingError::Misconfigured(format!("reqwest client: {e}")))?;

        let base = cfg.llm_base_url.trim_end_matches('/');
        let url = format!("{base}/embeddings");

        Ok(Self {
            client,
            url,
            api_key,
            model,
        })
    }
}

#[derive(Debug, Deserialize)]
struct EmbeddingsBody {
    data: Vec<EmbeddingData>,
    model: Option<String>,
}

#[derive(Debug, Deserialize)]
struct EmbeddingData {
    embedding: Vec<f32>,
}

#[async_trait]
impl EmbeddingProvider for OpenRouterEmbeddingProvider {
    async fn embed(&self, req: EmbedRequest) -> Result<EmbedResponse, EmbeddingError> {
        let body = json!({
            "model": self.model,
            "input": req.input,
        });

        let res = self
            .client
            .post(&self.url)
            .header(CONTENT_TYPE, "application/json")
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("HTTP-Referer", OPENROUTER_REFERER)
            .header("X-Title", OPENROUTER_TITLE)
            .header(USER_AGENT, "ai-radar-core")
            .json(&body)
            .send()
            .await
            .map_err(|e| EmbeddingError::Request(e.to_string()))?;

        let status = res.status();
        let text = res
            .text()
            .await
            .map_err(|e| EmbeddingError::Request(e.to_string()))?;

        if !status.is_success() {
            return Err(EmbeddingError::Request(format!(
                "HTTP {status}: {}",
                text.chars().take(400).collect::<String>()
            )));
        }

        let parsed: EmbeddingsBody = serde_json::from_str(&text).map_err(|e| {
            EmbeddingError::Request(format!("invalid embeddings JSON: {e}; body={text}"))
        })?;

        let first = parsed
            .data
            .into_iter()
            .next()
            .ok_or_else(|| EmbeddingError::Request("empty embeddings data".into()))?;

        let model = parsed.model.unwrap_or_else(|| self.model.clone());
        let dimensions = first.embedding.len();
        if dimensions == 0 {
            return Err(EmbeddingError::Request("empty embedding vector".into()));
        }

        Ok(EmbedResponse {
            model,
            dimensions,
            vector: first.embedding,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_sample_body() {
        let json = r#"{"data":[{"embedding":[0.1,0.2]}],"model":"test/embed"}"#;
        let body: EmbeddingsBody = serde_json::from_str(json).unwrap();
        assert_eq!(body.data[0].embedding.len(), 2);
    }
}
