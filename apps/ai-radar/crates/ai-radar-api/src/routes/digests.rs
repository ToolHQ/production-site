//! `GET /digests` and `GET /digests/:id` (**T-169**).

use axum::extract::{Path, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;
use uuid::Uuid;

use ai_radar_core::domain::Digest;
use ai_radar_core::repos::DigestRepository;

use crate::error::ApiError;
use crate::state::AppState;

#[derive(Debug, Serialize)]
pub struct DigestListResponse {
    pub items: Vec<Digest>,
    pub count: usize,
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/digests", get(list_recent))
        .route("/digests/:id", get(get_one))
}

async fn list_recent(
    State(state): State<AppState>,
) -> Result<(StatusCode, Json<DigestListResponse>), ApiError> {
    let items = state
        .digests
        .list_recent(50)
        .await
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;

    Ok((
        StatusCode::OK,
        Json(DigestListResponse {
            count: items.len(),
            items,
        }),
    ))
}

async fn get_one(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    headers: HeaderMap,
) -> Result<Response, ApiError> {
    let digest = state.digests.get(id).await?;

    let wants_markdown = headers
        .get(axum::http::header::ACCEPT)
        .and_then(|v| v.to_str().ok())
        .is_some_and(|v| v.contains("text/markdown"));

    if wants_markdown {
        Ok((
            StatusCode::OK,
            [(
                axum::http::header::CONTENT_TYPE,
                "text/markdown; charset=utf-8",
            )],
            digest.markdown_content,
        )
            .into_response())
    } else {
        Ok((StatusCode::OK, Json(digest)).into_response())
    }
}
