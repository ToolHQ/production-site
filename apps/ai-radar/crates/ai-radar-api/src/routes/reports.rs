//! `GET /reports/divergence` — human vs scorer mismatches (**T-170**).

use axum::extract::{Query, State};
use axum::http::StatusCode;
use axum::routing::get;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use ai_radar_core::pipeline::semantic_duplicates::{
    run_semantic_duplicates_report, SemanticDuplicatesReport, DEFAULT_SEMANTIC_DUP_THRESHOLD,
};
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

#[derive(Debug, Deserialize)]
pub struct SemanticDuplicatesQuery {
    #[serde(default = "default_semantic_threshold")]
    pub threshold: f32,
    #[serde(default = "default_limit")]
    pub limit: i64,
}

fn default_semantic_threshold() -> f32 {
    DEFAULT_SEMANTIC_DUP_THRESHOLD
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/reports/divergence", get(list_divergence))
        .route("/reports/duplicates", get(list_duplicates))
        .route("/reports/semantic-duplicates", get(list_semantic_duplicates))
}

async fn list_semantic_duplicates(
    State(state): State<AppState>,
    Query(q): Query<SemanticDuplicatesQuery>,
) -> Result<(StatusCode, Json<SemanticDuplicatesReport>), ApiError> {
    let report = run_semantic_duplicates_report(&state.db, &state.config, q.threshold, q.limit)
        .await
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;
    Ok((StatusCode::OK, Json(report)))
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
