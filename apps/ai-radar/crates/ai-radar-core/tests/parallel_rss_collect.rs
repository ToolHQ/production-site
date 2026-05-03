//! Parallel RSS collectors: one upstream 500 must not block the other (T-173 chaos slice).

use std::time::Duration;

use ai_radar_core::collector::rss::RssCollector;
use ai_radar_core::collector::Collector;
use ai_radar_core::domain::{Source, SourceType};
use chrono::Utc;
use uuid::Uuid;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

const MINIMAL_RSS: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>Ch</title>
<item><title>Hello</title><link>https://example.com/p</link><description>Body</description></item>
</channel></rss>"#;

#[tokio::test]
async fn parallel_collects_one_fails_one_succeeds() {
    let bad = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/bad.xml"))
        .respond_with(ResponseTemplate::new(500))
        .mount(&bad)
        .await;

    let good = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/ok.xml"))
        .respond_with(ResponseTemplate::new(200).set_body_string(MINIMAL_RSS))
        .mount(&good)
        .await;

    let client = RssCollector::default_http_client().expect("client");
    let c_fail = RssCollector::new(client.clone(), 10);
    let c_ok = RssCollector::new(client, 10);

    let source_bad = Source {
        id: Uuid::new_v4(),
        name: "bad".into(),
        source_type: SourceType::Rss,
        url: format!("{}/bad.xml", bad.uri()),
        enabled: true,
        poll_interval_minutes: 30,
        last_polled_at: None,
        last_error: None,
        metadata_json: serde_json::json!({}),
        created_at: Utc::now(),
        updated_at: Utc::now(),
    };
    let source_ok = Source {
        id: Uuid::new_v4(),
        name: "ok".into(),
        source_type: SourceType::Rss,
        url: format!("{}/ok.xml", good.uri()),
        enabled: true,
        poll_interval_minutes: 30,
        last_polled_at: None,
        last_error: None,
        metadata_json: serde_json::json!({}),
        created_at: Utc::now(),
        updated_at: Utc::now(),
    };

    let started = std::time::Instant::now();
    let (r_bad, r_ok) = tokio::join!(c_fail.collect(&source_bad), c_ok.collect(&source_ok));
    assert!(
        started.elapsed() < Duration::from_secs(20),
        "parallel collects should not serialize on one slow retrying feed"
    );

    assert!(r_bad.is_err(), "500 feed should error after retries");
    let items = r_ok.expect("good feed should parse");
    assert_eq!(items.len(), 1);
}
