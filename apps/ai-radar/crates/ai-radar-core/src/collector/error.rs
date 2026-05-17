//! Collector-facing errors (HTTP + feed parse).

use std::fmt::Write as _;

/// Failure while fetching or parsing an upstream feed.
#[derive(Debug, thiserror::Error)]
pub enum CollectError {
    /// Network / HTTP layer.
    #[error("fetch failed: {0}")]
    Fetch(String),
    /// Feed bytes could not be interpreted as RSS/Atom/JSON Feed.
    #[error("parse failed: {0}")]
    Parse(String),
    /// GitHub API rate limit exhausted (`x-ratelimit-*`).
    #[error("rate limited: {0}")]
    RateLimited(String),
}

impl CollectError {
    /// Map any [`reqwest::Error`] into a compact diagnostic string.
    #[must_use]
    pub fn from_reqwest(err: &reqwest::Error) -> Self {
        let mut msg = err.to_string();
        if let Some(status) = err.status() {
            let _ = write!(msg, " (HTTP {status})");
        }
        CollectError::Fetch(msg)
    }
}
