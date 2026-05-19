//! Health routes.
//!
//! - `GET /health` — cheap liveness (no DB); keeps the process alive during
//!   transient Postgres blips.
//! - `GET /health/ready` — readiness with `SELECT 1` (**T-264**).

use std::time::Duration;

use axum::extract::{Extension, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use crate::middleware::RequestId;
use crate::state::AppState;

/// Wall-clock budget for readiness `SELECT 1` (matches probe `timeoutSeconds`).
pub const READINESS_DB_TIMEOUT: Duration = Duration::from_secs(2);

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

/// Body returned by `GET /health/ready`.
#[derive(Debug, Serialize)]
pub struct ReadyResponse {
    pub status: &'static str,
    pub service: &'static str,
    pub version: &'static str,
    /// `"ok"` when Postgres answered `SELECT 1` within the timeout budget.
    pub database: &'static str,
}

/// Build the stateless `/health` sub-router (liveness).
pub fn router<S>() -> Router<S>
where
    S: Clone + Send + Sync + 'static,
{
    Router::new().route("/health", get(liveness_handler))
}

/// Build `/health/ready` (requires [`AppState`] + Postgres).
pub fn ready_router() -> Router<AppState> {
    Router::new().route("/health/ready", get(readiness_handler))
}

async fn liveness_handler(request_id: Option<Extension<RequestId>>) -> Json<HealthResponse> {
    if let Some(Extension(rid)) = request_id {
        tracing::debug!(request_id = rid.as_str(), "liveness probe");
    }
    Json(HealthResponse {
        status: "ok",
        service: "ai-radar-api",
        version: ai_radar_core::VERSION,
    })
}

async fn readiness_handler(
    State(state): State<AppState>,
    request_id: Option<Extension<RequestId>>,
) -> impl IntoResponse {
    if let Some(Extension(rid)) = request_id {
        tracing::debug!(request_id = rid.as_str(), "readiness probe");
    }

    match tokio::time::timeout(READINESS_DB_TIMEOUT, state.db.ping()).await {
        Ok(Ok(())) => (
            StatusCode::OK,
            Json(ReadyResponse {
                status: "ok",
                service: "ai-radar-api",
                version: ai_radar_core::VERSION,
                database: "ok",
            }),
        ),
        Ok(Err(e)) => {
            tracing::warn!(error = %e, "readiness: database ping failed");
            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(ReadyResponse {
                    status: "unavailable",
                    service: "ai-radar-api",
                    version: ai_radar_core::VERSION,
                    database: "unavailable",
                }),
            )
        }
        Err(_) => {
            tracing::warn!(
                timeout_secs = READINESS_DB_TIMEOUT.as_secs(),
                "readiness: database ping timed out"
            );
            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(ReadyResponse {
                    status: "unavailable",
                    service: "ai-radar-api",
                    version: ai_radar_core::VERSION,
                    database: "timeout",
                }),
            )
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;

    #[tokio::test]
    async fn health_returns_ok_payload() {
        let app: Router<()> = router();

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
