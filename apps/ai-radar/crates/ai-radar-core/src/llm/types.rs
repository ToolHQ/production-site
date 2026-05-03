//! Request/response DTOs for chat-style completions (OpenAI-compatible).

use serde::{Deserialize, Serialize};

/// A single chat completion request (system + user strings).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompletionRequest {
    /// System prompt (instructions).
    pub system: String,
    /// User / document payload.
    pub user: String,
    /// `max_tokens` passed to the provider (capped by the caller).
    pub max_tokens: u32,
    /// Sampling temperature.
    pub temperature: f32,
    /// When true, ask for `response_format: json_object` when the backend supports it.
    pub json_mode: bool,
}

impl Default for CompletionRequest {
    fn default() -> Self {
        Self {
            system: String::new(),
            user: String::new(),
            max_tokens: 512,
            temperature: 0.2,
            json_mode: false,
        }
    }
}

/// Normalized completion outcome (content + usage metadata).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CompletionResponse {
    /// Assistant message text (may be JSON when `json_mode` was used).
    pub content: String,
    /// Prompt tokens if the upstream reported usage.
    pub prompt_tokens: Option<u32>,
    /// Completion tokens if reported.
    pub completion_tokens: Option<u32>,
    /// Model identifier echoed by upstream.
    pub model: String,
    /// Wall-clock latency of the HTTP exchange in milliseconds.
    pub latency_ms: u64,
}
