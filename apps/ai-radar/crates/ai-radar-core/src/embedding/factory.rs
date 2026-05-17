//! Wiring from [`crate::config::AppConfig`].

use std::sync::Arc;

use tracing::warn;

use crate::config::AppConfig;

use super::noop::{MisconfiguredEmbeddingProvider, NoOpEmbeddingProvider};
use super::openrouter::OpenRouterEmbeddingProvider;
use super::EmbeddingProvider;

/// Build runtime embedding provider.
#[must_use]
pub fn build_embedding_provider(cfg: &AppConfig) -> Arc<dyn EmbeddingProvider> {
    if !cfg.embeddings_enabled {
        return Arc::new(NoOpEmbeddingProvider);
    }

    match OpenRouterEmbeddingProvider::try_new(cfg) {
        Ok(p) => Arc::new(p),
        Err(e) => {
            warn!(
                error = %e,
                "EMBEDDINGS_ENABLED=true but provider could not be constructed"
            );
            Arc::new(MisconfiguredEmbeddingProvider::new(e.to_string()))
        }
    }
}
