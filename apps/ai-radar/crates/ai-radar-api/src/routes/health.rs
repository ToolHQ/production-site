//! Health route.
//!
//! Cheap liveness probe consumed by the Kubernetes liveness/readiness/startup
//! probes (T-171). Intentionally has no dependencies on the database or LLM
//! provider so the API stays "up" even when downstream resources misbehave.

use axum::extract::Extension;
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use crate::middleware::RequestId;

/// Body returned by `GET /health`.
#[derive(Debug, Serialize)]
pub struct HealthResponse {
    /// Always `"ok"` while the process is accepting requests.
    pub status: &'static str,
    /// Service name, useful when several services share the same log sink.
    pub service: &'static str,
    /// Crate version, lifted from `CARGO_PKG_VERSION`.
    pub version: &'static str,
}

/// Build the `/health` sub-router.
pub fn router() -> Router {
    Router::new().route("/health", get(handler))
}

async fn handler(request_id: Option<Extension<RequestId>>) -> Json<HealthResponse> {
    if let Some(Extension(rid)) = request_id {
        tracing::debug!(request_id = rid.as_str(), "health probe");
    }
    Json(HealthResponse {
        status: "ok",
        service: "ai-radar-api",
        version: ai_radar_core::VERSION,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;

    #[tokio::test]
    async fn health_returns_ok_payload() {
        let app = router();

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/health")
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let bytes = to_bytes(response.into_body(), 1024).await.unwrap();
        let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(body["status"], "ok");
        assert_eq!(body["service"], "ai-radar-api");
        assert_eq!(body["version"], ai_radar_core::VERSION);
    }
}
