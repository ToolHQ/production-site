//! `GET /reports/divergence` — human vs scorer mismatches (**T-170**).

use axum::extract::{Query, State};
use axum::http::StatusCode;
use axum::routing::get;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use ai_radar_core::repos::{FeedbackRepository, RawItemRepository};

use crate::error::ApiError;
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct DivergenceQuery {
    #[serde(default = "default_limit")]
    pub limit: i64,
    #[serde(default)]
    pub offset: i64,
}

fn default_limit() -> i64 {
    50
}

#[derive(Debug, Serialize)]
pub struct DivergenceListResponse {
    pub items: Vec<ai_radar_core::repos::FeedbackDivergence>,
    pub count: usize,
    pub limit: i64,
    pub offset: i64,
}

#[derive(Debug, Serialize)]
pub struct DuplicateClusterResponse {
    pub clusters: Vec<ai_radar_core::repos::DuplicateCluster>,
    pub count: usize,
    pub limit: i64,
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/reports/divergence", get(list_divergence))
        .route("/reports/duplicates", get(list_duplicates))
}

async fn list_duplicates(
    State(state): State<AppState>,
    Query(q): Query<DivergenceQuery>,
) -> Result<(StatusCode, Json<DuplicateClusterResponse>), ApiError> {
    let limit = q.limit.clamp(1, 100);
    let clusters = state
        .raw_items
        .list_duplicate_clusters(limit)
        .await
        .map_err(ApiError::from)?;

    Ok((
        StatusCode::OK,
        Json(DuplicateClusterResponse {
            count: clusters.len(),
            limit,
            clusters,
        }),
    ))
}

async fn list_divergence(
    State(state): State<AppState>,
    Query(q): Query<DivergenceQuery>,
) -> Result<(StatusCode, Json<DivergenceListResponse>), ApiError> {
    let limit = q.limit.clamp(1, 100);
    let offset = q.offset.max(0);
    let items = state
        .feedback
        .list_divergences(limit, offset)
        .await
        .map_err(ApiError::from)?;

    Ok((
        StatusCode::OK,
        Json(DivergenceListResponse {
            count: items.len(),
            limit,
            offset,
            items,
        }),
    ))
}
