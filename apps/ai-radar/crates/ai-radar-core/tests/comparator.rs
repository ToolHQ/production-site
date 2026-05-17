//! Comparator fixtures and integration (**T-168**).

use ai_radar_core::comparator::{render_markdown, score_criteria, Comparator, ComparisonMatrix, ComparisonRow};
use ai_radar_core::db::Database;
use ai_radar_core::domain::{
    Decision, ExtractedItem, Maturity, NewExtractedItem, NewRawItem, NewScore, NewSource, RiskLevel,
    SourceType,
};
use ai_radar_core::repos::comparison::{ComparisonRepository, PgComparisonRepository};
use ai_radar_core::repos::extracted_item::{ExtractedItemRepository, PgExtractedItemRepository};
use ai_radar_core::repos::raw_item::{PgRawItemRepository, RawItemRepository};
use ai_radar_core::repos::score::{PgScoreRepository, ScoreRepository};
use ai_radar_core::repos::source::{PgSourceRepository, SourceRepository};
use chrono::Utc;
use uuid::Uuid;

const CATEGORY: &str = "LLM observability";

fn fixture_item(tool: &str, score_val: f32) -> (ExtractedItem, ai_radar_core::domain::Score) {
    let item = ExtractedItem {
        id: Uuid::new_v4(),
        raw_item_id: Uuid::new_v4(),
        version: 1,
        extractor: "llm-v1".into(),
        tool_name: Some(tool.into()),
        category: Some(CATEGORY.into()),
        summary: Some(format!("{tool} observability for Kubernetes with Helm.")),
        problem_solved: Some("Traces and metrics for LLM apps.".into()),
        self_hosted: Some(true),
        saas_only: Some(false),
        license: Some("Apache-2.0".into()),
        maturity: Some(Maturity::Stable),
        risk_level: Some(RiskLevel::Low),
        stack_fit: Some("k8s helm operator".into()),
        metadata_json: serde_json::json!({"days_since_activity": 10}),
        created_at: Utc::now(),
    };
    let score = ai_radar_core::domain::Score {
        id: Uuid::new_v4(),
        extracted_item_id: item.id,
        score: score_val,
        decision: Decision::Test,
        next_step: None,
        reasons_json: serde_json::json!([]),
        risks_json: serde_json::json!([]),
        scoring_version: "deterministic-v1".into(),
        metadata_json: serde_json::json!({}),
        created_at: Utc::now(),
    };
    (item, score)
}

#[test]
fn five_fixtures_same_category_produce_bounded_criteria() {
    let tools = ["Alpha", "Bravo", "Charlie", "Delta", "Echo"];
    for (i, name) in tools.iter().enumerate() {
        let (item, score) = fixture_item(name, 0.9 - (i as f32 * 0.05));
        let c = score_criteria(&item, &score);
        assert!(c.self_hosted <= 3);
        assert!(c.k8s_friendly >= 2);
        assert_eq!(item.category.as_deref(), Some(CATEGORY));
    }
}

#[test]
fn markdown_snapshot_non_empty_for_three_rows() {
    let mut rows = Vec::new();
    for (i, name) in ["A", "B", "C"].iter().enumerate() {
        let (item, score) = fixture_item(name, 0.8 - i as f32 * 0.1);
        rows.push(ComparisonRow {
            tool_name: item.tool_name.clone().unwrap(),
            extracted_item_id: item.id,
            overall_score: score.score,
            decision: score.decision,
            criteria: score_criteria(&item, &score),
        });
    }
    let md = render_markdown(&ComparisonMatrix {
        category: CATEGORY.into(),
        top_n: 3,
        rows,
    });
    assert!(md.contains("| A |"));
    assert!(md.contains("Self-hosted"));
}

async fn db_handle() -> Database {
    let url =
        std::env::var("DATABASE_URL").expect("DATABASE_URL must be set for ignored tests");
    Database::connect(&url).await.expect("connect")
}

async fn cleanup(pool: &sqlx::PgPool) {
    sqlx::query("TRUNCATE ai_radar.sources CASCADE")
        .execute(pool)
        .await
        .expect("cleanup");
}

async fn seed_scored_tool(
    db: &Database,
    slug: &str,
    category: &str,
    score_val: f32,
) -> Uuid {
    let src_id = PgSourceRepository::new(db)
        .create(&NewSource {
            name: format!("cmp-{slug}"),
            source_type: SourceType::Rss,
            url: format!("https://cmp.example.com/{slug}.xml"),
            enabled: None,
            poll_interval_minutes: None,
            metadata_json: None,
        })
        .await
        .unwrap()
        .id;
    let raw_id = PgRawItemRepository::new(db)
        .insert_idempotent(&NewRawItem {
            source_id: src_id,
            external_id: None,
            url: format!("https://cmp.example.com/{slug}"),
            title: None,
            raw_content: format!("body-{slug}"),
            content_hash: None,
            metadata_json: None,
            published_at: None,
        })
        .await
        .unwrap()
        .unwrap()
        .id;
    let extracted_id = PgExtractedItemRepository::new(db)
        .insert(&NewExtractedItem {
            raw_item_id: raw_id,
            extractor: "deterministic-v1".into(),
            tool_name: Some(format!("Tool-{slug}")),
            category: Some(category.into()),
            summary: Some("Kubernetes Helm observability stack.".into()),
            problem_solved: Some("LLM traces".into()),
            self_hosted: Some(true),
            license: Some("MIT".into()),
            maturity: Some(Maturity::Stable),
            stack_fit: Some("k8s".into()),
            ..Default::default()
        })
        .await
        .unwrap()
        .id;
    PgScoreRepository::new(db)
        .insert(&NewScore {
            extracted_item_id: extracted_id,
            score: score_val,
            decision: Decision::Adopt,
            next_step: None,
            reasons_json: None,
            risks_json: None,
            scoring_version: "deterministic-v1".into(),
            metadata_json: None,
        })
        .await
        .unwrap();
    extracted_id
}

#[tokio::test]
#[ignore = "requires Postgres; run: cargo test -p ai-radar-core --test comparator -- --ignored"]
async fn compare_persists_matrix_for_category() {
    let db = db_handle().await;
    cleanup(&db.pool).await;

    for (i, slug) in ["t1", "t2", "t3", "t4", "t5"].iter().enumerate() {
        seed_scored_tool(&db, slug, CATEGORY, 0.95 - i as f32 * 0.05).await;
    }
    // Different category — must not appear in matrix
    seed_scored_tool(&db, "other", "MCP servers", 0.99).await;

    let result = Comparator
        .compare(&db, CATEGORY, 5)
        .await
        .expect("compare");

    assert_eq!(result.comparison.category, CATEGORY);
    assert!(result.comparison.top_n >= 1);
    assert!(result.markdown.contains("Tool-t1"));
    assert!(!result.markdown.contains("Tool-other"));

    let loaded = PgComparisonRepository::new(&db)
        .get(result.comparison.id)
        .await
        .unwrap();
    assert_eq!(loaded.category, CATEGORY);
    let rows = loaded
        .matrix_json
        .get("rows")
        .and_then(|v| v.as_array())
        .map(|a| a.len())
        .unwrap_or(0);
    assert!(rows >= 3);
}
