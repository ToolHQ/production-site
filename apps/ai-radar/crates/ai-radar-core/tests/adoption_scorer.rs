//! Adoption signals in scorer rules and comparator (**T-230**).

use ai_radar_core::comparator::score_criteria;
use ai_radar_core::curation::adoption::{adoption_from_extracted, adoption_from_raw, StarsTier};
use ai_radar_core::curation::velocity::VelocityTier;
use ai_radar_core::domain::{
    Decision, ExtractedItem, Maturity, RawItem, RawItemStatus, RiskLevel, Score,
};
use ai_radar_core::metrics::{record_adoption_tier, record_velocity_tier};
use ai_radar_core::scorer::Scorer;
use chrono::Utc;
use serde_json::json;
use uuid::Uuid;

fn extracted_with_adoption(
    stars: i64,
    days_since_push: i64,
    velocity_tier: VelocityTier,
) -> ExtractedItem {
    let raw = RawItem {
        id: Uuid::new_v4(),
        source_id: Uuid::new_v4(),
        external_id: None,
        url: "https://github.com/o/r".into(),
        title: None,
        raw_content: "{}".into(),
        content_hash: "h".into(),
        status: RawItemStatus::Pending,
        metadata_json: json!({ "stargazers_count": stars }),
        tool_key: None,
        canonical_url: None,
        published_at: Some(Utc::now() - chrono::Duration::days(days_since_push)),
        collected_at: Utc::now(),
    };
    let mut adoption = adoption_from_raw(&raw).unwrap();
    adoption.velocity_tier = velocity_tier;
    ExtractedItem {
        id: Uuid::nil(),
        raw_item_id: raw.id,
        version: 1,
        extractor: "llm-v1".into(),
        tool_name: Some("popular-tool".into()),
        category: Some("devtools".into()),
        summary: Some("x".repeat(80)),
        problem_solved: Some("y".repeat(30)),
        self_hosted: Some(true),
        saas_only: Some(false),
        license: Some("MIT".into()),
        maturity: Some(Maturity::Stable),
        risk_level: Some(RiskLevel::Low),
        stack_fit: Some("kubernetes helm".into()),
        metadata_json: json!({
            "adoption": adoption.to_json(),
            "days_since_activity": days_since_push
        }),
        created_at: Utc::now(),
    }
}

#[test]
fn popular_repo_gets_adoption_rule_points() {
    let item = extracted_with_adoption(5_000, 5, VelocityTier::Unknown);
    let out = Scorer::v1().score(&item);
    assert!(
        out.reasons.iter().any(|r| r.contains("adoption_popular")),
        "expected adoption_popular rule: {:?}",
        out.reasons
    );
    assert!(out.points >= 60);
}

#[test]
fn dormant_repo_penalized() {
    let item = extracted_with_adoption(50, 200, VelocityTier::Unknown);
    let out = Scorer::v1().score(&item);
    assert!(
        out.risks.contains(&"stale_upstream".to_string()),
        "expected stale_upstream risk: {:?}",
        out.risks
    );
}

#[test]
fn comparator_community_uses_stars_tier() {
    let item = extracted_with_adoption(12_000, 3, VelocityTier::Unknown);
    let score = Score {
        id: Uuid::new_v4(),
        extracted_item_id: item.id,
        score: 0.9,
        decision: Decision::Adopt,
        next_step: None,
        reasons_json: json!([]),
        risks_json: json!([]),
        scoring_version: "deterministic-v1".into(),
        metadata_json: json!({}),
        created_at: Utc::now(),
    };
    let c = score_criteria(&item, &score);
    assert_eq!(c.community, 3);
    assert_eq!(
        adoption_from_raw(&RawItem {
            id: Uuid::new_v4(),
            source_id: Uuid::new_v4(),
            external_id: None,
            url: "https://github.com/o/r".into(),
            title: None,
            raw_content: "{}".into(),
            content_hash: "h".into(),
            status: RawItemStatus::Pending,
            metadata_json: json!({ "stargazers_count": 12_000 }),
            tool_key: None,
            canonical_url: None,
            published_at: Some(Utc::now() - chrono::Duration::days(3)),
            collected_at: Utc::now(),
        })
        .unwrap()
        .stars_tier,
        StarsTier::Viral
    );
}

#[test]
fn velocity_spike_rule_fires() {
    let item = extracted_with_adoption(5_000, 5, VelocityTier::Spike);
    let out = Scorer::v1().score(&item);
    assert!(
        out.reasons.iter().any(|r| r.contains("velocity_spike")),
        "expected velocity_spike: {:?}",
        out.reasons
    );
}

#[test]
fn velocity_stale_rule_fires() {
    let item = extracted_with_adoption(50, 200, VelocityTier::Declining);
    let out = Scorer::v1().score(&item);
    assert!(
        out.risks.contains(&"stagnant_momentum".to_string()),
        "expected stagnant_momentum: {:?}",
        out.risks
    );
}

#[test]
fn adoption_json_roundtrips_velocity() {
    let raw = RawItem {
        id: Uuid::new_v4(),
        source_id: Uuid::new_v4(),
        external_id: None,
        url: "https://github.com/o/r".into(),
        title: None,
        raw_content: "{}".into(),
        content_hash: "h".into(),
        status: RawItemStatus::Pending,
        metadata_json: json!({ "stargazers_count": 1000 }),
        tool_key: None,
        canonical_url: None,
        published_at: Some(Utc::now()),
        collected_at: Utc::now(),
    };
    let mut adoption = adoption_from_raw(&raw).unwrap();
    adoption.velocity_tier = VelocityTier::Growing;
    adoption.stars_delta_7d = Some(150);
    let meta = json!({ "adoption": adoption.to_json() });
    let parsed = adoption_from_extracted(&meta).unwrap();
    assert_eq!(parsed.velocity_tier, VelocityTier::Growing);
    assert_eq!(parsed.stars_delta_7d, Some(150));
}

#[test]
fn adoption_and_velocity_tier_metrics_emit() {
    let handle = metrics_exporter_prometheus::PrometheusBuilder::new()
        .install_recorder()
        .expect("recorder");
    ai_radar_core::metrics::describe_metrics();
    record_adoption_tier("adopt", "popular");
    record_velocity_tier("adopt", "spike");
    let rendered = handle.render();
    assert!(
        rendered.contains("ai_radar_adoption_tier_total"),
        "adoption metric missing: {rendered}"
    );
    assert!(
        rendered.contains("ai_radar_velocity_tier_total"),
        "velocity metric missing: {rendered}"
    );
}
