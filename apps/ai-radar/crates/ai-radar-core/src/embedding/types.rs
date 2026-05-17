//! Request/response types for embedding providers.

/// Single text input to embed.
#[derive(Debug, Clone)]
pub struct EmbedRequest {
    /// Text to vectorize (caller should truncate).
    pub input: String,
}

/// Normalized embedding vector from the provider.
#[derive(Debug, Clone, PartialEq)]
pub struct EmbedResponse {
    pub model: String,
    pub dimensions: usize,
    pub vector: Vec<f32>,
}
