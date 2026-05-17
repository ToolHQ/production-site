//! GitHub collector wiremock tests (**T-162**).

use ai_radar_core::collector::github::{GitHubClient, GithubCollector};
use ai_radar_core::collector::CollectError;
use ai_radar_core::collector::Collector;
use ai_radar_core::domain::{Source, SourceType};
use chrono::Utc;
use uuid::Uuid;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

fn gh_collector(server: &MockServer) -> GithubCollector {
    let http = reqwest::Client::builder().build().expect("client");
    let client = GitHubClient::new(http, None).with_api_base(server.uri());
    GithubCollector::new(client, 30)
}

fn source(source_type: SourceType, repo_url: &str) -> Source {
    Source {
        id: Uuid::new_v4(),
        name: "gh".into(),
        source_type,
        url: repo_url.into(),
        enabled: true,
        poll_interval_minutes: 60,
        last_polled_at: None,
        last_error: None,
        metadata_json: serde_json::json!({}),
        created_at: Utc::now(),
        updated_at: Utc::now(),
    }
}

#[tokio::test]
async fn releases_200_maps_external_id() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/repos/o/r/releases"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_string(r#"[{
                    "id": 9001,
                    "tag_name": "v1.0.0",
                    "name": "First",
                    "body": "Notes",
                    "html_url": "https://github.com/o/r/releases/tag/v1.0.0",
                    "published_at": "2026-01-01T00:00:00Z"
                }]"#)
                .insert_header("x-ratelimit-remaining", "10"),
        )
        .mount(&server)
        .await;

    let collector = gh_collector(&server);
    let items = collector
        .collect(&source(
            SourceType::GithubReleases,
            "https://github.com/o/r",
        ))
        .await
        .expect("collect");
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].external_id.as_deref(), Some("9001"));
    assert!(items[0].raw_content.contains("Notes"));
}

#[tokio::test]
async fn repo_meta_200_returns_json_snapshot() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/repos/o/r"))
        .respond_with(
            ResponseTemplate::new(200).set_body_string(
                r#"{
                "id": 42,
                "full_name": "o/r",
                "html_url": "https://github.com/o/r",
                "stargazers_count": 10,
                "forks_count": 2,
                "pushed_at": "2026-01-02T12:00:00Z"
            }"#,
            ),
        )
        .mount(&server)
        .await;

    let collector = gh_collector(&server);
    let items = collector
        .collect(&source(SourceType::GithubRepo, "https://github.com/o/r"))
        .await
        .expect("collect");
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].external_id.as_deref(), Some("repo:42"));
    assert!(items[0].raw_content.contains("stargazers_count"));
}

#[tokio::test]
async fn http_401_is_unauthorized() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/repos/o/r/releases"))
        .respond_with(ResponseTemplate::new(401).set_body_string("nope"))
        .mount(&server)
        .await;

    let collector = gh_collector(&server);
    let err = collector
        .collect(&source(
            SourceType::GithubReleases,
            "https://github.com/o/r",
        ))
        .await
        .expect_err("401");
    match err {
        CollectError::Fetch(msg) => {
            assert!(
                msg.contains("401") || msg.to_lowercase().contains("unauthorized"),
                "{msg}"
            );
        }
        e => panic!("expected Fetch, got {e:?}"),
    }
}

#[tokio::test]
async fn http_403_rate_limit_message() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/repos/o/r/releases"))
        .respond_with(ResponseTemplate::new(403).set_body_string(
            r#"{"message":"API rate limit exceeded"}"#,
        ))
        .mount(&server)
        .await;

    let collector = gh_collector(&server);
    let err = collector
        .collect(&source(
            SourceType::GithubReleases,
            "https://github.com/o/r",
        ))
        .await
        .expect_err("403");
    match err {
        CollectError::RateLimited(_) => {}
        e => panic!("expected RateLimited, got {e:?}"),
    }
}

#[tokio::test]
async fn http_500_surfaces_after_retries() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/repos/o/r/releases"))
        .respond_with(ResponseTemplate::new(500).set_body_string("fail"))
        .mount(&server)
        .await;

    let collector = gh_collector(&server);
    let err = collector
        .collect(&source(
            SourceType::GithubReleases,
            "https://github.com/o/r",
        ))
        .await
        .expect_err("500");
    match err {
        CollectError::Fetch(msg) => assert!(msg.contains("500"), "{msg}"),
        e => panic!("expected Fetch, got {e:?}"),
    }
}

#[tokio::test]
async fn pagination_follows_link_next() {
    use wiremock::matchers::query_param;

    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/repos/o/r/releases"))
        .and(query_param("per_page", "30"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_string(r#"[{"id":1,"tag_name":"a","html_url":"https://github.com/o/r/a","body":"a"}]"#)
                .insert_header(
                    "link",
                    format!(
                        r#"<{}/repos/o/r/releases?page=2>; rel="next""#,
                        server.uri()
                    ),
                ),
        )
        .mount(&server)
        .await;
    Mock::given(method("GET"))
        .and(path("/repos/o/r/releases"))
        .and(query_param("page", "2"))
        .respond_with(ResponseTemplate::new(200).set_body_string(
            r#"[{"id":2,"tag_name":"b","html_url":"https://github.com/o/r/b","body":"b"}]"#,
        ))
        .mount(&server)
        .await;

    let collector = gh_collector(&server);
    let items = collector
        .collect(&source(
            SourceType::GithubReleases,
            "https://github.com/o/r",
        ))
        .await
        .expect("collect");
    assert_eq!(items.len(), 2);
    assert_eq!(items[1].external_id.as_deref(), Some("2"));
}
