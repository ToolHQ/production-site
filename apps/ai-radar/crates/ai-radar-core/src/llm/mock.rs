//! Deterministic providers for unit tests (no network).

use std::sync::Arc;

use async_trait::async_trait;
use sha2::{Digest, Sha256};

use super::error::LlmError;
use super::types::{CompletionRequest, CompletionResponse};
use super::LlmProvider;

#[derive(Debug, Clone)]
enum MockMode {
    Fixed {
        content: String,
        model: String,
    },
    /// Content is `mock:<sha256_hex>` of `system\\0user` (stable across runs).
    PromptHash {
        model: String,
    },
}

/// Returns a fixed string or a hash of the prompt — useful in tests.
#[derive(Debug, Clone)]
pub struct MockLlmProvider {
    mode: MockMode,
}

impl MockLlmProvider {
    /// Build a mock that always returns `content` with zero usage metadata.
    #[must_use]
    pub fn fixed(content: impl Into<String>) -> Self {
        Self {
            mode: MockMode::Fixed {
                content: content.into(),
                model: "mock/fixed".to_string(),
            },
        }
    }

    /// Fixed content with a custom model label in the response.
    #[must_use]
    pub fn with_model(content: impl Into<String>, model: impl Into<String>) -> Self {
        Self {
            mode: MockMode::Fixed {
                content: content.into(),
                model: model.into(),
            },
        }
    }

    /// Echo a deterministic digest of the concatenated prompts (T-164).
    #[must_use]
    pub fn prompt_hash() -> Self {
        Self {
            mode: MockMode::PromptHash {
                model: "mock/prompt-hash".to_string(),
            },
        }
    }

    fn hash_content(req: &CompletionRequest) -> String {
        let mut hasher = Sha256::new();
        hasher.update(req.system.as_bytes());
        hasher.update([0_u8]);
        hasher.update(req.user.as_bytes());
        let digest = hasher.finalize();
        format!("mock:{digest:x}")
    }
}

#[async_trait]
impl LlmProvider for MockLlmProvider {
    async fn complete(&self, req: CompletionRequest) -> Result<CompletionResponse, LlmError> {
        let (content, model) = match &self.mode {
            MockMode::Fixed { content, model } => (content.clone(), model.clone()),
            MockMode::PromptHash { model } => (Self::hash_content(&req), model.clone()),
        };

        Ok(CompletionResponse {
            content,
            prompt_tokens: Some(0),
            completion_tokens: Some(0),
            model,
            latency_ms: 0,
        })
    }
}

/// Wrap as trait object.
#[must_use]
pub fn mock_arc(content: impl Into<String>) -> Arc<dyn LlmProvider> {
    Arc::new(MockLlmProvider::fixed(content))
}

#[cfg(test)]
mod tests {
    use super::super::types::CompletionRequest;
    use super::*;

    #[tokio::test]
    async fn prompt_hash_is_stable_for_same_prompts() {
        let p = MockLlmProvider::prompt_hash();
        let req = CompletionRequest {
            system: "a".into(),
            user: "b".into(),
            ..CompletionRequest::default()
        };
        let a = p.complete(req.clone()).await.unwrap().content;
        let b = p.complete(req).await.unwrap().content;
        assert_eq!(a, b);
        assert!(a.starts_with("mock:"));
    }

    #[tokio::test]
    async fn prompt_hash_changes_when_user_changes() {
        let p = MockLlmProvider::prompt_hash();
        let r1 = CompletionRequest {
            user: "x".into(),
            ..CompletionRequest::default()
        };
        let r2 = CompletionRequest {
            user: "y".into(),
            ..CompletionRequest::default()
        };
        let a = p.complete(r1).await.unwrap().content;
        let b = p.complete(r2).await.unwrap().content;
        assert_ne!(a, b);
    }
}
