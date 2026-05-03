//! Exponential backoff retries for transient LLM failures.

use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use tokio::time::sleep;
use tracing::Instrument;

use super::error::LlmError;
use super::types::{CompletionRequest, CompletionResponse};
use super::LlmProvider;

const MAX_ATTEMPTS: u32 = 3;
const DEFAULT_BACKOFF_MS: &[u64] = &[1000, 2000, 4000];

/// Retries `complete` on [`LlmError::RateLimited`] and [`LlmError::Server`] only.
pub struct RetryingLlmProvider {
    inner: Arc<dyn LlmProvider>,
    backoff_ms: Box<[u64]>,
}

impl RetryingLlmProvider {
    /// Wrap any provider with the retry policy from T-164 (1s / 2s / 4s ±20% jitter).
    #[must_use]
    pub fn new(inner: Arc<dyn LlmProvider>) -> Self {
        Self {
            inner,
            backoff_ms: DEFAULT_BACKOFF_MS.into(),
        }
    }

    /// Same semantics as [`Self::new`] but with explicit backoff gaps (milliseconds).
    #[must_use]
    pub fn with_backoff_ms(inner: Arc<dyn LlmProvider>, backoff_ms: impl Into<Box<[u64]>>) -> Self {
        Self {
            inner,
            backoff_ms: backoff_ms.into(),
        }
    }

    fn should_retry(err: &LlmError) -> bool {
        matches!(err, LlmError::RateLimited(_) | LlmError::Server(_))
    }

    async fn backoff_after_attempt(&self, attempt: u32) {
        let idx = (attempt - 1) as usize;
        let base_ms = self
            .backoff_ms
            .get(idx)
            .copied()
            .or_else(|| self.backoff_ms.last().copied())
            .unwrap_or(4000);
        let jitter_bps = fastrand::u64(800..=1200);
        let millis = base_ms.saturating_mul(jitter_bps) / 1000;
        sleep(Duration::from_millis(millis.max(1))).await;
    }
}

#[async_trait]
impl LlmProvider for RetryingLlmProvider {
    async fn complete(&self, req: CompletionRequest) -> Result<CompletionResponse, LlmError> {
        let span = tracing::info_span!(
            "llm.complete",
            attempt = tracing::field::Empty,
            model = tracing::field::Empty,
            prompt_tokens = tracing::field::Empty,
            completion_tokens = tracing::field::Empty,
            latency_ms = tracing::field::Empty,
            llm.cost_estimate_usd = tracing::field::Empty,
        );

        async {
            let mut last_err = LlmError::Server("no attempts".into());

            for attempt in 1..=MAX_ATTEMPTS {
                tracing::Span::current().record("attempt", attempt);

                match self.inner.complete(req.clone()).await {
                    Ok(resp) => {
                        tracing::Span::current().record("model", &resp.model);
                        tracing::Span::current()
                            .record("prompt_tokens", resp.prompt_tokens.unwrap_or(0));
                        tracing::Span::current()
                            .record("completion_tokens", resp.completion_tokens.unwrap_or(0));
                        tracing::Span::current().record("latency_ms", resp.latency_ms);

                        let est = super::cost::approx_cost_usd(
                            &resp.model,
                            resp.prompt_tokens,
                            resp.completion_tokens,
                        );
                        tracing::Span::current().record("llm.cost_estimate_usd", est);

                        tracing::info!(
                            model = %resp.model,
                            prompt_tokens = ?resp.prompt_tokens,
                            completion_tokens = ?resp.completion_tokens,
                            latency_ms = resp.latency_ms,
                            llm.cost_estimate_usd = est,
                            "llm completion succeeded"
                        );

                        return Ok(resp);
                    }
                    Err(e) if Self::should_retry(&e) && attempt < MAX_ATTEMPTS => {
                        tracing::warn!(
                            error = %e,
                            attempt,
                            max_attempts = MAX_ATTEMPTS,
                            "llm transient error; retrying"
                        );
                        last_err = e;
                        self.backoff_after_attempt(attempt).await;
                    }
                    Err(e) => return Err(e),
                }
            }

            Err(last_err)
        }
        .instrument(span)
        .await
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicU32, Ordering};
    use std::sync::Arc;

    use async_trait::async_trait;

    use super::super::types::{CompletionRequest, CompletionResponse};
    use super::super::LlmProvider;
    use super::{LlmError, RetryingLlmProvider};

    struct Flaky {
        calls: AtomicU32,
    }

    impl Flaky {
        fn new() -> Self {
            Self {
                calls: AtomicU32::new(0),
            }
        }
    }

    #[async_trait]
    impl LlmProvider for Flaky {
        async fn complete(&self, _req: CompletionRequest) -> Result<CompletionResponse, LlmError> {
            let n = self.calls.fetch_add(1, Ordering::SeqCst);
            if n < 2 {
                return Err(LlmError::RateLimited("forced".into()));
            }
            Ok(CompletionResponse {
                content: "ok".into(),
                prompt_tokens: Some(1),
                completion_tokens: Some(1),
                model: "mock/flaky".into(),
                latency_ms: 0,
            })
        }
    }

    #[tokio::test]
    async fn retries_rate_limit_then_succeeds() {
        let inner: Arc<dyn LlmProvider> = Arc::new(Flaky::new());
        let retrying = RetryingLlmProvider::with_backoff_ms(inner, [1_u64, 1, 1]);
        let out = retrying
            .complete(CompletionRequest::default())
            .await
            .expect("third attempt succeeds");
        assert_eq!(out.content, "ok");
    }
}
