//! `GET /stats` — pipeline row counts (visible “radar” surface before extract/digest).

use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};

use ai_radar_core::repos::{load_pipeline_stats_with_embeddings, PipelineStats};

use crate::error::ApiError;
use crate::state::AppState;

/// Router for aggregate statistics.
pub fn router() -> Router<AppState> {
    Router::new().route("/stats", get(handler))
}

async fn handler(State(state): State<AppState>) -> Result<Json<PipelineStats>, ApiError> {
    let snapshot = load_pipeline_stats_with_embeddings(
        &state.db,
        state.config.embeddings_enabled,
        state.config.embedding_model.as_deref(),
    )
    .await?;
    Ok(Json(snapshot))
}
