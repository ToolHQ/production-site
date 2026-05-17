//! Provider wiring from [`crate::config::AppConfig`].

use std::sync::Arc;

use tracing::warn;

use crate::config::AppConfig;

use super::noop::{MisconfiguredLlmProvider, NoOpLlmProvider};
use super::openrouter::OpenRouterLlmProvider;
use super::pace::PacingLlmProvider;
use super::retry::RetryingLlmProvider;
use super::LlmProvider;

/// Build the runtime LLM provider for this process.
///
/// - `LLM_ENABLED=false` → [`NoOpLlmProvider`] (fails fast with [`super::LlmError::Disabled`]).
/// - `LLM_ENABLED=true` → [`RetryingLlmProvider`] around [`OpenRouterLlmProvider`], or
///   [`MisconfiguredLlmProvider`] when secrets/model are missing.
#[must_use]
pub fn build_llm_provider(cfg: &AppConfig) -> Arc<dyn LlmProvider> {
    if !cfg.llm_enabled {
        return Arc::new(NoOpLlmProvider);
    }

    match OpenRouterLlmProvider::try_new(cfg) {
        Ok(p) => {
            let http: Arc<dyn LlmProvider> = Arc::new(p);
            let paced: Arc<dyn LlmProvider> = if cfg.llm_max_rpm > 0 {
                Arc::new(PacingLlmProvider::new(http, cfg.llm_max_rpm))
            } else {
                http
            };
            Arc::new(RetryingLlmProvider::new(paced))
        }
        Err(e) => {
            warn!(
                error = %e,
                "LLM_ENABLED=true but provider could not be constructed; completions will return misconfigured errors"
            );
            Arc::new(MisconfiguredLlmProvider::new(e.to_string()))
        }
    }
}
