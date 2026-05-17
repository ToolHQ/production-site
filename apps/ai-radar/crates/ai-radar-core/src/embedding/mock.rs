//! Deterministic mock embeddings for tests.

use async_trait::async_trait;

use super::error::EmbeddingError;
use super::types::{EmbedRequest, EmbedResponse};
use super::EmbeddingProvider;

/// Hash input into a fixed-size pseudo-vector (not semantic; tests only).
#[derive(Debug, Default)]
pub struct MockEmbeddingProvider {
    pub dimensions: usize,
}

impl MockEmbeddingProvider {
    /// Create with vector length (default 8).
    #[must_use]
    pub fn new(dimensions: usize) -> Self {
        Self {
            dimensions: dimensions.max(4),
        }
    }
}

#[async_trait]
impl EmbeddingProvider for MockEmbeddingProvider {
    async fn embed(&self, req: EmbedRequest) -> Result<EmbedResponse, EmbeddingError> {
        let mut vector = vec![0.0_f32; self.dimensions];
        for (i, b) in req.input.bytes().enumerate() {
            vector[i % self.dimensions] += f32::from(b % 251) / 251.0;
        }
        let norm: f32 = vector.iter().map(|x| x * x).sum::<f32>().sqrt();
        if norm > f32::EPSILON {
            for x in &mut vector {
                *x /= norm;
            }
        }
        Ok(EmbedResponse {
            model: "mock".into(),
            dimensions: self.dimensions,
            vector,
        })
    }
}
