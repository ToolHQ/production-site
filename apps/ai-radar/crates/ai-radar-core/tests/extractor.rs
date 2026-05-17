//! LLM extractor behaviour tests (**T-165**).

use std::sync::Arc;

use ai_radar_core::domain::{NewRawItem, RawItem};
use ai_radar_core::extractor::{llm_extract_with_retry, parse_extracted_fields, ExtractedFields};
use ai_radar_core::llm::{
    CompletionRequest, CompletionResponse, LlmError, LlmProvider, MockLlmProvider,
};
use async_trait::async_trait;
use uuid::Uuid;

#[tokio::test]
async fn llm_roundtrip_accepts_clean_json() {
    let json = r#"{"tool_name":"curl","category":"cli","summary":"transfer tool"}"#;
    let llm: Arc<dyn LlmProvider> = Arc::new(MockLlmProvider::fixed(json));
    let raw = fake_raw("hello");
    let mut audits = Vec::new();
    let (fields, _) = llm_extract_with_retry(&llm, &raw, &mut audits)
        .await
        .expect("mock json");
    assert_eq!(fields.tool_name.as_deref(), Some("curl"));
    assert_eq!(audits.len(), 1);
    assert_eq!(audits[0]["kind"], "success");
}

#[tokio::test]
async fn llm_roundtrip_strips_json_fence_from_mock() {
    let fenced = "```json\n{\"tool_name\":\"x\"}\n```";
    let llm: Arc<dyn LlmProvider> = Arc::new(MockLlmProvider::fixed(fenced));
    let raw = fake_raw("body");
    let mut audits = Vec::new();
    let (fields, _) = llm_extract_with_retry(&llm, &raw, &mut audits)
        .await
        .expect("fence");
    assert_eq!(fields.tool_name.as_deref(), Some("x"));
}

#[tokio::test]
async fn llm_roundtrip_fails_after_two_parse_errors() {
    let llm: Arc<dyn LlmProvider> = Arc::new(JunkLlmProvider);
    let raw = fake_raw("body");
    let mut audits = Vec::new();
    let err = llm_extract_with_retry(&llm, &raw, &mut audits)
        .await
        .expect_err("junk");
    assert!(matches!(err, LlmError::Parse(_)));
    assert_eq!(audits.len(), 2);
    assert_eq!(audits[0]["kind"], "parse_error");
    assert_eq!(audits[1]["kind"], "parse_error");
}

#[test]
fn parse_extracted_accepts_partial_object() {
    let j = r#"{"tool_name":"t"}"#;
    let f: ExtractedFields = parse_extracted_fields(j).expect("partial");
    assert_eq!(f.tool_name.as_deref(), Some("t"));
    assert!(f.category.is_none());
}

fn fake_raw(content: &str) -> RawItem {
    RawItem {
        id: Uuid::new_v4(),
        source_id: Uuid::new_v4(),
        external_id: Some("e1".into()),
        url: "https://example.com/p".into(),
        title: Some("Title".into()),
        raw_content: content.into(),
        content_hash: NewRawItem::compute_hash(content),
        status: ai_radar_core::domain::RawItemStatus::Pending,
        metadata_json: serde_json::json!({}),
        tool_key: None,
        canonical_url: None,
        published_at: None,
        collected_at: chrono::Utc::now(),
    }
}

/// Always returns non-JSON assistant text (forces two parse retries).
#[derive(Debug)]
struct JunkLlmProvider;

#[async_trait]
impl LlmProvider for JunkLlmProvider {
    async fn complete(&self, _req: CompletionRequest) -> Result<CompletionResponse, LlmError> {
        Ok(CompletionResponse {
            content: "this is not json".into(),
            prompt_tokens: Some(0),
            completion_tokens: Some(0),
            model: "mock/junk".into(),
            latency_ms: 0,
        })
    }
}
