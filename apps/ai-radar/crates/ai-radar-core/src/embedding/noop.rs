//! No-op embedding provider when disabled.

use async_trait::async_trait;

use super::error::EmbeddingError;
use super::types::{EmbedRequest, EmbedResponse};
use super::EmbeddingProvider;

/// Fails fast with [`EmbeddingError::Disabled`].
#[derive(Debug, Default)]
pub struct NoOpEmbeddingProvider;

#[async_trait]
impl EmbeddingProvider for NoOpEmbeddingProvider {
    async fn embed(&self, _req: EmbedRequest) -> Result<EmbedResponse, EmbeddingError> {
        Err(EmbeddingError::Disabled)
    }
}

/// Surfaces configuration errors without panicking at startup.
#[derive(Debug, Clone)]
pub struct MisconfiguredEmbeddingProvider {
    message: String,
}

impl MisconfiguredEmbeddingProvider {
    /// Wrap a human-readable misconfiguration reason.
    #[must_use]
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

#[async_trait]
impl EmbeddingProvider for MisconfiguredEmbeddingProvider {
    async fn embed(&self, _req: EmbedRequest) -> Result<EmbedResponse, EmbeddingError> {
        Err(EmbeddingError::Misconfigured(self.message.clone()))
    }
}
