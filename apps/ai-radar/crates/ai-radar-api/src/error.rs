//! HTTP error type wrapping [`RepoError`] and other handler errors.
//!
//! Every handler returns `Result<_, ApiError>` so the conversion to a
//! JSON body and status code is centralized, predictable, and easy to
//! audit (no leaking SQL details to clients).

use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Serialize;

use ai_radar_core::db::RepoError;

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
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, error_code, message) = match &self {
            ApiError::Repo(RepoError::NotFound) => (
                StatusCode::NOT_FOUND,
                "not_found",
                "resource not found".to_string(),
            ),
            ApiError::Repo(RepoError::Conflict(msg)) => {
                (StatusCode::CONFLICT, "conflict", msg.clone())
            }
            ApiError::Repo(RepoError::Validation(msg)) => {
                (StatusCode::UNPROCESSABLE_ENTITY, "validation", msg.clone())
            }
            ApiError::Repo(RepoError::Database(_)) => {
                tracing::error!(error = %self, "database error");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "database_error",
                    "internal database error".to_string(),
                )
            }
            ApiError::BadRequest(msg) => (StatusCode::BAD_REQUEST, "bad_request", msg.clone()),
        };

        let body = Json(ApiErrorBody {
            error: error_code,
            message,
        });
        (status, body).into_response()
    }
}
