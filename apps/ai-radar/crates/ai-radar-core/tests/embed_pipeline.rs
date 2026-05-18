//! Embed pipeline unit tests (**T-248**).

use ai_radar_core::domain::{ExtractedItem, Maturity, RiskLevel};
use ai_radar_core::embedding::{EmbedRequest, EmbeddingProvider, MockEmbeddingProvider};
use ai_radar_core::pipeline::embed::build_embed_text;
use ai_radar_core::util::limits::MAX_EXTRACT_INPUT_CHARS;
use chrono::Utc;
use uuid::Uuid;

fn sample_item() -> ExtractedItem {
    ExtractedItem {
        id: Uuid::new_v4(),
        raw_item_id: Uuid::new_v4(),
        version: 1,
        extractor: "test".into(),
        tool_name: Some("CoolTool".into()),
        category: Some("observability".into()),
        summary: Some("Metrics and traces for k8s.".into()),
        problem_solved: Some("Reduce MTTR.".into()),
        self_hosted: Some(true),
        saas_only: Some(false),
        license: None,
        maturity: Some(Maturity::Stable),
        risk_level: Some(RiskLevel::Low),
        stack_fit: None,
        metadata_json: serde_json::json!({}),
        created_at: Utc::now(),
    }
}

#[test]
fn build_embed_text_joins_fields() {
    let text = build_embed_text(&sample_item());
    assert!(text.contains("CoolTool"));
    assert!(text.contains("observability"));
    assert!(text.contains("Metrics"));
    assert!(text.contains("MTTR"));
}

#[test]
fn build_embed_text_truncates_at_extract_limit() {
    let mut item = sample_item();
    item.summary = Some("x".repeat(MAX_EXTRACT_INPUT_CHARS + 500));
    let text = build_embed_text(&item);
    assert!(text.len() <= MAX_EXTRACT_INPUT_CHARS);
}

#[tokio::test]
async fn mock_provider_embeds_build_text() {
    let p = MockEmbeddingProvider::new(8);
    let text = build_embed_text(&sample_item());
    let resp = p.embed(EmbedRequest { input: text }).await.unwrap();
    assert_eq!(resp.dimensions, 8);
    assert_eq!(resp.vector.len(), 8);
}
