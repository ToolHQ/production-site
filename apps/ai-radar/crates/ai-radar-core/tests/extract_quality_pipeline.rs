//! Extract pipeline + quality gate integration (**T-232**).

use std::sync::Arc;

use ai_radar_core::domain::{NewRawItem, RawItem, RawItemStatus};
use ai_radar_core::extractor::assess_extract_quality;
use ai_radar_core::llm::{LlmProvider, MockLlmProvider};
use uuid::Uuid;

#[test]
fn quality_gate_rejects_sparse_json() {
    let fields = ai_radar_core::extractor::parse_extracted_fields(r#"{"tool_name":"x"}"#)
        .expect("parse");
    let report = assess_extract_quality(&fields);
    assert_eq!(report.tier, ai_radar_core::extractor::QualityTier::Reject);
}

#[test]
fn quality_gate_accepts_rich_json() {
    let pad = "x".repeat(80);
    let json = format!(
        r#"{{
        "tool_name": "Ollama",
        "category": "LLM runtime",
        "summary": "{pad}",
        "problem_solved": "Runs local models with minimal configuration on developer laptops.",
        "self_hosted": true,
        "saas_only": false,
        "license": "MIT"
    }}"#
    );
    let fields = ai_radar_core::extractor::parse_extracted_fields(&json).expect("parse");
    let report = assess_extract_quality(&fields);
    assert_eq!(report.tier, ai_radar_core::extractor::QualityTier::Pass);
}

#[tokio::test]
async fn mock_llm_sparse_then_quality_reject_tier() {
    let json = r#"{"tool_name":"only-name"}"#;
    let llm: Arc<dyn LlmProvider> = Arc::new(MockLlmProvider::fixed(json));
    let raw = fake_raw("body");
    let mut audits = Vec::new();
    let (fields, _) = ai_radar_core::extractor::llm_extract_with_retry(&llm, &raw, &mut audits)
        .await
        .expect("llm");
    let report = assess_extract_quality(&fields);
    assert_eq!(report.tier, ai_radar_core::extractor::QualityTier::Reject);
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
        status: RawItemStatus::Pending,
        metadata_json: serde_json::json!({}),
        published_at: None,
        collected_at: chrono::Utc::now(),
    }
}
