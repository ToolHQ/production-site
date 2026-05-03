//! Errors returned by [`super::LlmProvider`](super::LlmProvider) implementations.

/// Failure modes for LLM HTTP calls and response parsing.
#[derive(Debug, Clone, thiserror::Error)]
pub enum LlmError {
    /// LLM calls are disabled via configuration.
    #[error("LLM is disabled (LLM_ENABLED=false); enable it to use completions")]
    Disabled,

    /// Missing model, key, or invalid client options when LLM is enabled.
    #[error("LLM misconfigured: {0}")]
    Misconfigured(String),

    /// Authentication / authorization rejected by upstream.
    #[error("LLM auth failed: {0}")]
    Auth(String),

    /// Upstream rate limit (HTTP 429).
    #[error("LLM rate limited: {0}")]
    RateLimited(String),

    /// Upstream server error (5xx) or overloaded.
    #[error("LLM server error: {0}")]
    Server(String),

    /// Request timed out.
    #[error("LLM request timed out")]
    Timeout,

    /// Response body could not be interpreted as expected JSON.
    #[error("LLM response parse error: {0}")]
    Parse(String),

    /// Other HTTP status from upstream.
    #[error("LLM HTTP {0}: {1}")]
    Http(u16, String),
}
