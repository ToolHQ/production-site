//! HTTP error type wrapping [`RepoError`] and other handler errors.
//!
//! Every handler returns `Result<_, ApiError>` so the conversion to a
//! JSON body and status code is centralized, predictable, and easy to
//! audit (no leaking SQL details to clients).

use axum::http::{HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Serialize;

use ai_radar_core::db::RepoError;

/// Seconds clients should wait before retrying a 503 (**T-265**).
pub const RETRY_AFTER_SECS: u64 = 5;

/// Body shape for every error response.
#[derive(Debug, Serialize)]
pub struct ApiErrorBody {
    /// Stable machine-readable error code.
    pub error: &'static str,
    /// Human-readable description.
    pub message: String,
}

/// Errors surfaced by the HTTP handlers.
#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    /// Repository error from `ai-radar-core`.
    #[error(transparent)]
    Repo(#[from] RepoError),

    /// Bad request body or query string.
    #[error("bad request: {0}")]
    BadRequest(String),

    /// Transient overload or timeout (**T-265**).
    #[error("service unavailable: {0}")]
    ServiceUnavailable(String),
}

impl ApiError {
    /// Map a repository error; transient DB faults become 503.
    #[must_use]
    pub fn from_repo(err: RepoError) -> Self {
        if err.is_transient() {
            ApiError::ServiceUnavailable(
                "database temporarily unavailable; retry shortly".into(),
            )
        } else {
            ApiError::Repo(err)
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, error_code, message, retry_after) = match &self {
            ApiError::Repo(RepoError::NotFound) => (
                StatusCode::NOT_FOUND,
                "not_found",
                "resource not found".to_string(),
                None,
            ),
            ApiError::Repo(RepoError::Conflict(msg)) => {
                (StatusCode::CONFLICT, "conflict", msg.clone(), None)
            }
            ApiError::Repo(RepoError::Validation(msg)) => (
                StatusCode::UNPROCESSABLE_ENTITY,
                "validation",
                msg.clone(),
                None,
            ),
            ApiError::Repo(RepoError::Database(_)) => {
                tracing::error!(error = %self, "database error");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "database_error",
                    "internal database error".to_string(),
                    None,
                )
            }
            ApiError::BadRequest(msg) => {
                (StatusCode::BAD_REQUEST, "bad_request", msg.clone(), None)
            }
            ApiError::ServiceUnavailable(msg) => (
                StatusCode::SERVICE_UNAVAILABLE,
                "service_unavailable",
                msg.clone(),
                Some(RETRY_AFTER_SECS),
            ),
        };

        let body = Json(ApiErrorBody {
            error: error_code,
            message,
        });
        let mut response = (status, body).into_response();
        if let Some(secs) = retry_after {
            if let Ok(value) = HeaderValue::from_str(&secs.to_string()) {
                response
                    .headers_mut()
                    .insert(axum::http::header::RETRY_AFTER, value);
            }
        }
        response
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;
    use sqlx::Error as SqlxError;

    #[test]
    fn transient_pool_timeout_maps_to_service_unavailable() {
        let err = RepoError::Database(Box::new(SqlxError::PoolTimedOut));
        let api = ApiError::from_repo(err);
        matches!(api, ApiError::ServiceUnavailable(_));
    }

    #[tokio::test]
    async fn service_unavailable_includes_retry_after_header() {
        let response = ApiError::ServiceUnavailable("busy".into()).into_response();
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert_eq!(
            response
                .headers()
                .get(axum::http::header::RETRY_AFTER)
                .and_then(|v| v.to_str().ok()),
            Some("5")
        );
        let bytes = to_bytes(response.into_body(), 512).await.unwrap();
        let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(body["error"], "service_unavailable");
    }
}
