use ai_radar_core::domain::{Decision, DigestType};
use ai_radar_core::pipeline::digest::{render_markdown, DigestData, DigestItem};
use chrono::TimeZone;
use uuid::Uuid;

#[test]
fn digest_markdown_includes_all_sections_and_items() {
    let data = DigestData {
        digest_type: DigestType::Weekly,
        period_start: chrono::Utc.with_ymd_and_hms(2026, 5, 1, 0, 0, 0).unwrap(),
        period_end: chrono::Utc.with_ymd_and_hms(2026, 5, 8, 0, 0, 0).unwrap(),
        adopt: vec![DigestItem {
            raw_item_id: Uuid::new_v4(),
            extracted_item_id: Uuid::new_v4(),
            score_id: Uuid::new_v4(),
            score: 0.91,
            decision: Decision::Adopt,
            tool_name: Some("ToolA".into()),
            category: Some("observability".into()),
            url: "https://example.com/a".into(),
            title: Some("A title".into()),
            reasons: vec!["self-hosted".into(), "k8s-friendly".into()],
            risks: vec!["early".into()],
            next_step: Some("Spike this week".into()),
        }],
        test: vec![],
        monitor: vec![],
        ignore: vec![],
    };

    let md = render_markdown(&data);
    assert!(md.contains("# AI Radar Digest — 2026-05-08"));
    assert!(md.contains("## ✅ Adotar"));
    assert!(md.contains("### 1. ToolA"));
    assert!(md.contains("**Categoria:** observability"));
    assert!(md.contains("**Score:** 91/100"));
    assert!(md.contains("**Fonte:** https://example.com/a"));
    assert!(md.contains("## Resumo executivo"));
    assert!(md.contains("## 🔥 Testar"));
    assert!(md.contains("## 👀 Monitorar"));
    assert!(md.contains("## ❌ Ignorar"));
}
