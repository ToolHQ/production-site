//! Webpage collector tests (**T-163**).

use ai_radar_core::collector::web::{extract, WebCollector, WebFetcher, WebFetcherConfig, MAX_FETCH_BYTES};
use ai_radar_core::collector::CollectError;
use ai_radar_core::collector::Collector;
use ai_radar_core::domain::{Source, SourceType};
use chrono::Utc;
use uuid::Uuid;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

#[test]
fn cleaner_strips_script_from_fixture() {
    let html = include_str!("fixtures/web/with_script.html");
    let clean = extract(html).expect("extract");
    assert!(!clean.text.to_lowercase().contains("alert"));
    assert!(clean.text.contains("Visible paragraph"));
}

#[tokio::test]
async fn fetch_rejects_stream_over_1mb() {
    let server = MockServer::start().await;
    let chunk = "x".repeat(32_768);
    let body = chunk.repeat(40); // > 1MB
    Mock::given(method("GET"))
        .and(path("/huge"))
        .respond_with(ResponseTemplate::new(200).set_body_string(body))
        .mount(&server)
        .await;

    let client = WebFetcher::default_http_client().expect("client");
    let fetcher = WebFetcher::new(client, WebFetcherConfig::default());
    let err = fetcher
        .fetch(&format!("{}/huge", server.uri()))
        .await
        .expect_err("oversize");
    match err {
        CollectError::Fetch(msg) => {
            assert!(
                msg.contains(&MAX_FETCH_BYTES.to_string()) || msg.contains("exceeds"),
                "{msg}"
            );
        }
        e => panic!("expected Fetch, got {e:?}"),
    }
}

#[tokio::test]
async fn collector_produces_clean_item() {
    let html = include_str!("fixtures/web/minimal.html");
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/doc"))
        .respond_with(ResponseTemplate::new(200).set_body_string(html))
        .mount(&server)
        .await;

    let client = WebFetcher::default_http_client().expect("client");
    let collector = WebCollector::new(WebFetcher::new(client, WebFetcherConfig::default()));
    let source = Source {
        id: Uuid::new_v4(),
        name: "web".into(),
        source_type: SourceType::Webpage,
        url: format!("{}/doc", server.uri()),
        enabled: true,
        poll_interval_minutes: 60,
        last_polled_at: None,
        last_error: None,
        metadata_json: serde_json::json!({}),
        created_at: Utc::now(),
        updated_at: Utc::now(),
    };
    let items = collector.collect(&source).await.expect("collect");
    assert_eq!(items.len(), 1);
    assert!(items[0].raw_content.contains("Hello"));
    assert_eq!(items[0].title.as_deref(), Some("Minimal"));
}
