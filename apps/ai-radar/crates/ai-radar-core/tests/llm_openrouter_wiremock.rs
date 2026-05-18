//! HTTP contract tests for [`ai_radar_core::llm::OpenRouterLlmProvider`] (wiremock).

use std::time::Duration;

use ai_radar_core::config::{
    AppConfig, DEFAULT_API_BIND, DEFAULT_EMBED_BATCH_LIMIT, DEFAULT_LOG_LEVEL,
    DEFAULT_POST_EXTRACT_EMBED_TAIL_LIMIT,
};
use ai_radar_core::llm::{
    build_llm_provider, CompletionRequest, LlmError, LlmProvider, OpenRouterLlmProvider,
};
use serde_json::json;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

fn llm_test_cfg(server: &MockServer) -> AppConfig {
    AppConfig {
        api_bind: DEFAULT_API_BIND.to_string(),
        log_level: DEFAULT_LOG_LEVEL.to_string(),
        database_url: None,
        llm_enabled: true,
        llm_base_url: format!("{}/v1", server.uri().trim_end_matches('/')),
        llm_api_key: Some("sk-test".into()),
        llm_model: Some("fixture-model".into()),
        llm_timeout_seconds: 5,
        llm_max_rpm: 0,
        github_token: None,
        collect_concurrency: 2,
        max_items_per_run: 50,
        llm_scoring_enabled: false,
        llm_scoring_deterministic_weight: 0.7,
        llm_scoring_llm_weight: 0.3,
        embeddings_enabled: false,
        embedding_model: None,
        embed_batch_limit: DEFAULT_EMBED_BATCH_LIMIT,
        post_extract_embed_tail_limit: DEFAULT_POST_EXTRACT_EMBED_TAIL_LIMIT,
    }
}

#[tokio::test]
async fn maps_200_json_to_completion_response() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/v1/chat/completions"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "choices": [{"message": {"content": "pong"}}],
            "model": "fixture-model",
            "usage": {"prompt_tokens": 3, "completion_tokens": 1}
        })))
        .mount(&server)
        .await;

    let cfg = llm_test_cfg(&server);
    let provider = OpenRouterLlmProvider::try_new(&cfg).expect("fixture config");
    let out = provider
        .complete(CompletionRequest {
            system: "sys".into(),
            user: "ping".into(),
            max_tokens: 16,
            temperature: 0.0,
            json_mode: false,
        })
        .await
        .expect("200 maps to Ok");

    assert_eq!(out.content, "pong");
    assert_eq!(out.prompt_tokens, Some(3));
    assert_eq!(out.completion_tokens, Some(1));
    assert_eq!(out.model, "fixture-model");
}

#[tokio::test]
async fn json_mode_sets_response_format() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/v1/chat/completions"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "choices": [{"message": {"content": "{}"}}],
            "model": "fixture-model",
            "usage": {"prompt_tokens": 1, "completion_tokens": 1}
        })))
        .mount(&server)
        .await;

    let cfg = llm_test_cfg(&server);
    let provider = OpenRouterLlmProvider::try_new(&cfg).expect("fixture config");
    provider
        .complete(CompletionRequest {
            system: "sys".into(),
            user: "u".into(),
            max_tokens: 8,
            temperature: 0.0,
            json_mode: true,
        })
        .await
        .expect("json_mode completion");

    let recorded = server.received_requests().await.expect("requests");
    assert_eq!(recorded.len(), 1);
    let body: serde_json::Value = serde_json::from_slice(&recorded[0].body).expect("json body");
    assert_eq!(body["response_format"]["type"], "json_object");
}

#[tokio::test]
async fn maps_401_to_auth() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/v1/chat/completions"))
        .respond_with(ResponseTemplate::new(401).set_body_string("nope"))
        .mount(&server)
        .await;

    let cfg = llm_test_cfg(&server);
    let provider = OpenRouterLlmProvider::try_new(&cfg).expect("fixture config");
    let err = provider
        .complete(CompletionRequest::default())
        .await
        .expect_err("401 must error");
    assert!(matches!(err, LlmError::Auth(_)));
}

#[tokio::test]
async fn maps_429_to_rate_limited() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/v1/chat/completions"))
        .respond_with(ResponseTemplate::new(429).set_body_string("slow down"))
        .mount(&server)
        .await;

    let cfg = llm_test_cfg(&server);
    let provider = OpenRouterLlmProvider::try_new(&cfg).expect("fixture config");
    let err = provider
        .complete(CompletionRequest::default())
        .await
        .expect_err("429 must error");
    assert!(matches!(err, LlmError::RateLimited(_)));
}

#[tokio::test]
async fn maps_500_to_server() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/v1/chat/completions"))
        .respond_with(ResponseTemplate::new(500).set_body_string("boom"))
        .mount(&server)
        .await;

    let cfg = llm_test_cfg(&server);
    let provider = OpenRouterLlmProvider::try_new(&cfg).expect("fixture config");
    let err = provider
        .complete(CompletionRequest::default())
        .await
        .expect_err("500 must error");
    assert!(matches!(err, LlmError::Server(_)));
}

#[tokio::test]
async fn slow_upstream_maps_to_timeout() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/v1/chat/completions"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_delay(Duration::from_secs(10))
                .set_body_json(json!({
                    "choices": [{"message": {"content": "late"}}],
                    "model": "fixture-model"
                })),
        )
        .mount(&server)
        .await;

    let mut cfg = llm_test_cfg(&server);
    cfg.llm_timeout_seconds = 1;

    let provider = OpenRouterLlmProvider::try_new(&cfg).expect("fixture config");
    let err = provider
        .complete(CompletionRequest::default())
        .await
        .expect_err("must time out");
    assert!(matches!(err, LlmError::Timeout));
}

#[tokio::test]
async fn factory_disabled_returns_noop() {
    let server = MockServer::start().await;
    let mut cfg = llm_test_cfg(&server);
    cfg.llm_enabled = false;

    let p = build_llm_provider(&cfg);
    let err = p
        .complete(CompletionRequest::default())
        .await
        .expect_err("noop must refuse");
    assert!(matches!(err, LlmError::Disabled));
}

#[tokio::test]
async fn factory_misconfigured_when_enabled_without_api_key() {
    let server = MockServer::start().await;
    let mut cfg = llm_test_cfg(&server);
    cfg.llm_api_key = None;

    let p = build_llm_provider(&cfg);
    let err = p
        .complete(CompletionRequest::default())
        .await
        .expect_err("misconfigured provider must error");
    assert!(matches!(err, LlmError::Misconfigured(_)));
}
