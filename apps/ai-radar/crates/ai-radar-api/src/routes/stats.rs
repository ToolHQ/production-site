//! `GET /stats` — pipeline row counts (visible “radar” surface before extract/digest).

use std::time::Duration;

use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};
use tokio::time::timeout;

use ai_radar_core::repos::{load_pipeline_stats_degraded, PipelineStats};

use crate::error::ApiError;
use crate::state::AppState;

/// Wall-clock budget for aggregate stats queries.
const STATS_QUERY_TIMEOUT: Duration = Duration::from_secs(5);

/// Router for aggregate statistics.
pub fn router() -> Router<AppState> {
    Router::new().route("/stats", get(handler))
}

async fn handler(State(state): State<AppState>) -> Result<Json<PipelineStats>, ApiError> {
    let fut = load_pipeline_stats_degraded(
        &state.db,
        state.config.embeddings_enabled,
        state.config.embedding_model.as_deref(),
    );
    match timeout(STATS_QUERY_TIMEOUT, fut).await {
        Ok(Ok(snapshot)) => Ok(Json(snapshot)),
        Ok(Err(e)) => Err(ApiError::from_repo(e)),
        Err(_) => Err(ApiError::ServiceUnavailable(
            "stats query timed out; retry shortly".into(),
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stats_timeout_constant_is_reasonable() {
        assert!(STATS_QUERY_TIMEOUT.as_secs() >= 3);
        assert!(STATS_QUERY_TIMEOUT.as_secs() <= 15);
    }
}
