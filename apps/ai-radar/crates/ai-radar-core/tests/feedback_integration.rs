//! Feedback repository integration (**T-170**).

use ai_radar_core::db::Database;
use ai_radar_core::domain::{
    Decision, FeedbackType, NewExtractedItem, NewFeedback, NewRawItem, NewScore, NewSource,
    SourceType,
};
use ai_radar_core::repos::extracted_item::{ExtractedItemRepository, PgExtractedItemRepository};
use ai_radar_core::repos::feedback::{FeedbackRepository, PgFeedbackRepository};
use ai_radar_core::repos::raw_item::{PgRawItemRepository, RawItemRepository};
use ai_radar_core::repos::score::{PgScoreRepository, ScoreRepository};
use ai_radar_core::repos::source::{PgSourceRepository, SourceRepository};
use uuid::Uuid;

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

async fn seed_adopt_scored(db: &Database, slug: &str) -> Uuid {
    let src_id = PgSourceRepository::new(db)
        .create(&NewSource {
            name: format!("fb-{slug}"),
            source_type: SourceType::Rss,
            url: format!("https://fb.example.com/{slug}.xml"),
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
            url: format!("https://fb.example.com/{slug}"),
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
            category: Some("testing".into()),
            ..Default::default()
        })
        .await
        .unwrap()
        .id;
    PgScoreRepository::new(db)
        .insert(&NewScore {
            extracted_item_id: extracted_id,
            score: 0.88,
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
#[ignore = "requires Postgres; run: cargo test -p ai-radar-core --test feedback_integration -- --ignored"]
async fn feedback_roundtrip_lists_two_entries() {
    let db = db_handle().await;
    cleanup(&db.pool).await;
    let extracted_id = seed_adopt_scored(&db, "roundtrip").await;
    let repo = PgFeedbackRepository::new(&db);

    repo.insert(&NewFeedback {
        extracted_item_id: extracted_id,
        feedback_type: FeedbackType::Useful,
        notes: Some("ok".into()),
    })
    .await
    .unwrap();

    repo.insert(&NewFeedback {
        extracted_item_id: extracted_id,
        feedback_type: FeedbackType::Rejected,
        notes: Some("not for us".into()),
    })
    .await
    .unwrap();

    let list = repo.list_for_item(extracted_id).await.unwrap();
    assert_eq!(list.len(), 2);
    assert_eq!(list[0].feedback_type, FeedbackType::Rejected);

    cleanup(&db.pool).await;
}

#[tokio::test]
#[ignore = "requires Postgres; run: cargo test -p ai-radar-core --test feedback_integration -- --ignored"]
async fn divergence_report_includes_reject_on_adopt() {
    let db = db_handle().await;
    cleanup(&db.pool).await;
    let extracted_id = seed_adopt_scored(&db, "diverge").await;
    let repo = PgFeedbackRepository::new(&db);

    repo.insert(&NewFeedback {
        extracted_item_id: extracted_id,
        feedback_type: FeedbackType::Rejected,
        notes: None,
    })
    .await
    .unwrap();

    let rows = repo.list_divergences(20, 0).await.unwrap();
    assert!(
        rows.iter()
            .any(|r| r.extracted_item_id == extracted_id && r.decision == Decision::Adopt),
        "rejected feedback on adopt decision must appear in divergence report"
    );

    cleanup(&db.pool).await;
}

#[test]
fn invalid_feedback_type_is_rejected_at_parse() {
    assert!(FeedbackType::parse("tested_bad").is_err());
    assert!(FeedbackType::parse("").is_err());
}
