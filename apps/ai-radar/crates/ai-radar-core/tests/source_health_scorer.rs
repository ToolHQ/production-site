//! Source health in scorer rules (**T-238**).

use ai_radar_core::curation::source_health::{source_health_from_extracted, SourceHealthTier};
use ai_radar_core::domain::{ExtractedItem, Maturity, RiskLevel};
use ai_radar_core::metrics::record_source_health_tier;
use ai_radar_core::scorer::Scorer;
use chrono::Utc;
use serde_json::json;
use uuid::Uuid;

fn extracted_with_health(tier: SourceHealthTier) -> ExtractedItem {
    let health = json!({
        "source_id": Uuid::new_v4(),
        "source_name": "lobsters",
        "tier": tier.as_str(),
        "raw_total": 100,
        "raw_failed": 30,
        "raw_skipped": 0,
        "extracted_total": 10,
        "quality_warn": 0
    });
    ExtractedItem {
        id: Uuid::nil(),
        raw_item_id: Uuid::new_v4(),
        version: 1,
        extractor: "llm-v1".into(),
        tool_name: Some("tool".into()),
        category: Some("devtools".into()),
        summary: Some("x".repeat(80)),
        problem_solved: Some("y".repeat(30)),
        self_hosted: Some(true),
        saas_only: Some(false),
        license: Some("MIT".into()),
        maturity: Some(Maturity::Stable),
        risk_level: Some(RiskLevel::Low),
        stack_fit: Some("kubernetes".into()),
        metadata_json: json!({ "source_health": health }),
        created_at: Utc::now(),
    }
}

#[test]
fn noisy_source_rule_fires() {
    let item = extracted_with_health(SourceHealthTier::Noisy);
    let out = Scorer::v1().score(&item);
    assert!(
        out.reasons.iter().any(|r| r.contains("source_noisy")),
        "expected source_noisy: {:?}",
        out.reasons
    );
    assert!(out.risks.contains(&"noisy_feed".to_string()));
}

#[test]
fn health_json_roundtrips() {
    let item = extracted_with_health(SourceHealthTier::Degraded);
    let parsed = source_health_from_extracted(&item.metadata_json).unwrap();
    assert_eq!(parsed.tier, SourceHealthTier::Degraded);
}

#[test]
fn source_health_metric_emits() {
    let handle = metrics_exporter_prometheus::PrometheusBuilder::new()
        .install_recorder()
        .expect("recorder");
    ai_radar_core::metrics::describe_metrics();
    record_source_health_tier("monitor", "noisy");
    assert!(
        handle.render().contains("ai_radar_source_health_tier_total"),
        "metric missing"
    );
}
