//! `/sources` routes — list and create.

use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::get;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use ai_radar_core::domain::{NewSource, Source, SourceType};
use ai_radar_core::curation::SourceHealthSnapshot;
use ai_radar_core::repos::{PgSourceHealthRepository, SourceHealthRepository, SourceRepository};

use crate::error::ApiError;
use crate::state::AppState;

/// JSON body for `POST /sources`.
///
/// Mirrors [`NewSource`] but exposes `source_type` as a string for
/// ergonomic clients. Parsing errors come back as `400 Bad Request`.
#[derive(Debug, Deserialize)]
pub struct CreateSourceRequest {
    /// Human-readable label.
    pub name: String,
    /// One of `rss`, `github_repo`, `github_releases`, `webpage`,
    /// `youtube`.
    pub source_type: String,
    /// Upstream URL.
    pub url: String,
    /// Optional initial enabled flag (defaults to `true`).
    #[serde(default)]
    pub enabled: Option<bool>,
    /// Optional polling cadence (defaults to 30 minutes).
    #[serde(default)]
    pub poll_interval_minutes: Option<i32>,
    /// Optional metadata blob.
    #[serde(default)]
    pub metadata_json: Option<serde_json::Value>,
}

/// JSON envelope returned by `GET /sources`.
#[derive(Debug, Serialize)]
pub struct ListSourcesResponse {
    /// Sources, ordered by name.
    pub items: Vec<Source>,
    /// Number of items returned.
    pub count: usize,
}

/// Build the `/sources` sub-router.
/// JSON envelope for `GET /sources/health`.
#[derive(Debug, Serialize)]
pub struct ListSourceHealthResponse {
    pub items: Vec<SourceHealthSnapshot>,
    pub count: usize,
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/sources", get(list).post(create))
        .route("/sources/enabled", get(list_enabled))
        .route("/sources/health", get(list_health))
}

async fn list_health(
    State(state): State<AppState>,
) -> Result<Json<ListSourceHealthResponse>, ApiError> {
    let repo = PgSourceHealthRepository::new(&state.db);
    let items = repo.list_all().await.map_err(ApiError::from_repo)?;
    let count = items.len();
    Ok(Json(ListSourceHealthResponse { items, count }))
}

async fn list(State(state): State<AppState>) -> Result<Json<ListSourcesResponse>, ApiError> {
    let items = state.sources.list_all().await.map_err(ApiError::from_repo)?;
    let count = items.len();
    Ok(Json(ListSourcesResponse { items, count }))
}

async fn list_enabled(
    State(state): State<AppState>,
) -> Result<Json<ListSourcesResponse>, ApiError> {
    let items = state
        .sources
        .list_enabled()
        .await
        .map_err(ApiError::from_repo)?;
    let count = items.len();
    Ok(Json(ListSourcesResponse { items, count }))
}

async fn create(
    State(state): State<AppState>,
    Json(body): Json<CreateSourceRequest>,
) -> Result<(StatusCode, Json<Source>), ApiError> {
    let source_type = SourceType::parse(&body.source_type)
        .map_err(|v| ApiError::BadRequest(format!("unknown source_type '{v}'")))?;

    let payload = NewSource {
        name: body.name,
        source_type,
        url: body.url,
        enabled: body.enabled,
        poll_interval_minutes: body.poll_interval_minutes,
        metadata_json: body.metadata_json,
    };

    let created = state.sources.create(&payload).await?;
    Ok((StatusCode::CREATED, Json(created)))
}
