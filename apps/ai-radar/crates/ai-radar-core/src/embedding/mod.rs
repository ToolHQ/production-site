//! Embedding provider abstraction (**T-247**).

mod cosine;
mod error;
mod factory;
mod mock;
mod noop;
mod openrouter;
mod types;

pub use cosine::cosine_similarity;
pub use error::EmbeddingError;
pub use factory::build_embedding_provider;
pub use mock::MockEmbeddingProvider;
pub use noop::{MisconfiguredEmbeddingProvider, NoOpEmbeddingProvider};
pub use openrouter::OpenRouterEmbeddingProvider;
pub use types::{EmbedRequest, EmbedResponse};

use async_trait::async_trait;

/// Async text embedding provider (OpenRouter-compatible HTTP).
#[async_trait]
pub trait EmbeddingProvider: Send + Sync {
    /// Embed a single text chunk.
    ///
    /// # Errors
    ///
    /// See [`EmbeddingError`].
    async fn embed(&self, req: EmbedRequest) -> Result<EmbedResponse, EmbeddingError>;
}
