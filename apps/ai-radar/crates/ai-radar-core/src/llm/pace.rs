//! Minimum spacing between outbound LLM HTTP calls (OpenRouter free-tier RPM).

use std::sync::Arc;
use std::time::{Duration, Instant};

use async_trait::async_trait;
use tokio::sync::Mutex;

use super::error::LlmError;
use super::types::{CompletionRequest, CompletionResponse};
use super::LlmProvider;

/// Enforces at most `max_rpm` completions per rolling minute (gap = 60s / rpm).
pub struct PacingLlmProvider {
    inner: Arc<dyn LlmProvider>,
    min_gap: Duration,
    last: Mutex<Instant>,
}

impl PacingLlmProvider {
    /// Wrap `inner` with spacing derived from `max_rpm` (values `< 1` clamp to 1).
    #[must_use]
    pub fn new(inner: Arc<dyn LlmProvider>, max_rpm: u32) -> Self {
        let rpm = max_rpm.max(1);
        let min_gap = Duration::from_millis(60_000 / u64::from(rpm));
        Self {
            inner,
            min_gap,
            last: Mutex::new(Instant::now() - min_gap),
        }
    }

    async fn wait_turn(&self) {
        let mut guard = self.last.lock().await;
        let elapsed = guard.elapsed();
        if elapsed < self.min_gap {
            tokio::time::sleep(self.min_gap - elapsed).await;
        }
        *guard = Instant::now();
    }
}

#[async_trait]
impl LlmProvider for PacingLlmProvider {
    async fn complete(&self, req: CompletionRequest) -> Result<CompletionResponse, LlmError> {
        self.wait_turn().await;
        self.inner.complete(req).await
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicU32, Ordering};
    use std::sync::Arc;
    use std::time::Instant;

    use async_trait::async_trait;

    use super::*;
    use crate::llm::types::{CompletionRequest, CompletionResponse};

    struct Counting {
        calls: AtomicU32,
    }

    #[async_trait]
    impl LlmProvider for Counting {
        async fn complete(
            &self,
            _req: CompletionRequest,
        ) -> Result<CompletionResponse, LlmError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            Ok(CompletionResponse {
                content: "{}".into(),
                prompt_tokens: Some(1),
                completion_tokens: Some(1),
                model: "mock".into(),
                latency_ms: 0,
            })
        }
    }

    #[tokio::test]
    async fn enforces_minimum_gap_for_60_rpm() {
        let inner: Arc<dyn LlmProvider> = Arc::new(Counting {
            calls: AtomicU32::new(0),
        });
        let paced = PacingLlmProvider::new(inner, 60); // 1s gap
        let started = Instant::now();
        paced
            .complete(CompletionRequest::default())
            .await
            .unwrap();
        paced
            .complete(CompletionRequest::default())
            .await
            .unwrap();
        assert!(
            started.elapsed() >= Duration::from_millis(900),
            "second call should wait ~1s"
        );
    }
}
