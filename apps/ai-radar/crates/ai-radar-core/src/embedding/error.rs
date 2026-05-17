//! Embedding provider errors (**T-247**).

/// Failure modes for embedding HTTP and configuration.
#[derive(Debug, thiserror::Error)]
pub enum EmbeddingError {
    /// Embeddings disabled via `EMBEDDINGS_ENABLED=false`.
    #[error("embeddings are disabled")]
    Disabled,
    /// Missing API key, model, or invalid client setup.
    #[error("embedding provider misconfigured: {0}")]
    Misconfigured(String),
    /// Upstream HTTP or parse failure.
    #[error("embedding request failed: {0}")]
    Request(String),
}
