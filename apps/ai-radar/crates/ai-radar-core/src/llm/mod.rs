//! LLM provider abstraction (T-164): OpenAI-compatible HTTP, mocks, retries.

mod cost;
mod error;
mod factory;
mod mock;
mod noop;
mod openrouter;
mod retry;
mod types;

pub use cost::approx_cost_usd;
pub use error::LlmError;
pub use factory::build_llm_provider;
pub use mock::{mock_arc, MockLlmProvider};
pub use noop::{MisconfiguredLlmProvider, NoOpLlmProvider};
pub use openrouter::{openrouter_arc, OpenRouterLlmProvider};
pub use retry::RetryingLlmProvider;
pub use types::{CompletionRequest, CompletionResponse};

use async_trait::async_trait;

/// Async chat completion provider (OpenRouter, mocks, no-op).
#[async_trait]
pub trait LlmProvider: Send + Sync {
    /// Perform one completion request.
    ///
    /// # Errors
    ///
    /// See [`LlmError`] for transport, auth, and parse failures.
    async fn complete(&self, req: CompletionRequest) -> Result<CompletionResponse, LlmError>;
}
