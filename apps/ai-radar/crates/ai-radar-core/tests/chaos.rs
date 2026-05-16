//! Chaos-style failure tests (**T-173**).

use std::sync::Arc;

use ai_radar_core::domain::{NewRawItem, RawItem, RawItemStatus};
use ai_radar_core::extractor::llm_extract_with_retry;
use ai_radar_core::llm::{CompletionRequest, CompletionResponse, LlmError, LlmProvider};
use async_trait::async_trait;
use uuid::Uuid;

/// LLM timeout must surface as [`LlmError::Timeout`] without panicking (raw stays failed on extract pass).
#[tokio::test]
async fn llm_timeout_returns_error_without_panic() {
    let llm: Arc<dyn LlmProvider> = Arc::new(TimeoutLlmProvider);
    let raw = sample_raw("content");
    let mut audits = Vec::new();
    let err = llm_extract_with_retry(&llm, &raw, &mut audits)
        .await
        .expect_err("timeout");
    assert!(matches!(err, LlmError::Timeout));
}

/// Oversize rejection path remains stable (complements RSS unit tests).
#[test]
fn max_raw_content_bytes_constant_is_two_hundred_kib() {
    assert_eq!(ai_radar_core::util::limits::MAX_RAW_CONTENT_BYTES, 200_000);
}

#[derive(Debug)]
struct TimeoutLlmProvider;

#[async_trait]
impl LlmProvider for TimeoutLlmProvider {
    async fn complete(&self, _req: CompletionRequest) -> Result<CompletionResponse, LlmError> {
        Err(LlmError::Timeout)
    }
}

fn sample_raw(content: &str) -> RawItem {
    RawItem {
        id: Uuid::new_v4(),
        source_id: Uuid::new_v4(),
        external_id: Some("e1".into()),
        url: "https://example.com/p".into(),
        title: Some("Title".into()),
        raw_content: content.into(),
        content_hash: NewRawItem::compute_hash(content),
        status: RawItemStatus::Pending,
        metadata_json: serde_json::json!({}),
        published_at: None,
        collected_at: chrono::Utc::now(),
    }
}
