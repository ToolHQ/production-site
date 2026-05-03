//! Provider that refuses all calls — used when `LLM_ENABLED=false`.

use async_trait::async_trait;

use super::error::LlmError;
use super::types::{CompletionRequest, CompletionResponse};
use super::LlmProvider;

/// Fast-fail provider for deterministic-only deployments.
#[derive(Debug, Default)]
pub struct NoOpLlmProvider;

/// Always returns [`LlmError::Misconfigured`] — used when `LLM_ENABLED=true` but init failed.
#[derive(Debug, Clone)]
pub struct MisconfiguredLlmProvider {
    message: String,
}

impl MisconfiguredLlmProvider {
    /// Wrap a human-readable reason (logged at factory time).
    #[must_use]
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

#[async_trait]
impl LlmProvider for NoOpLlmProvider {
    async fn complete(&self, _req: CompletionRequest) -> Result<CompletionResponse, LlmError> {
        Err(LlmError::Disabled)
    }
}

#[async_trait]
impl LlmProvider for MisconfiguredLlmProvider {
    async fn complete(&self, _req: CompletionRequest) -> Result<CompletionResponse, LlmError> {
        Err(LlmError::Misconfigured(self.message.clone()))
    }
}
