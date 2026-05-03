//! `POST /score/run` — deterministic scoring pass (**T-166**).

use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::post;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use ai_radar_core::pipeline::score::{run_score, DEFAULT_SCORE_STALE_HOURS};

use crate::error::ApiError;
use crate::state::AppState;

fn default_score_limit() -> i64 {
    50
}

fn default_stale_hours() -> i64 {
    DEFAULT_SCORE_STALE_HOURS
}

/// JSON body for `POST /score/run`.
#[derive(Debug, Deserialize)]
pub struct ScoreRunRequest {
    /// Max extracted rows to process.
    #[serde(default = "default_score_limit")]
    pub limit: i64,
    /// Hours since last `deterministic-v1` score before re-eligibility.
    #[serde(default = "default_stale_hours")]
    pub stale_hours: i64,
    /// When true, ignore the recency window (always eligible up to `limit`).
    #[serde(default)]
    pub rescore_all: bool,
}

/// JSON response for `POST /score/run`.
#[derive(Debug, Serialize)]
pub struct ScoreRunResponse {
    /// Rows scored successfully.
    pub scored: u64,
    /// Rows that failed insert.
    pub failed: u64,
}

/// Mount `/score` routes.
pub fn router() -> Router<AppState> {
    Router::new().route("/score/run", post(run))
}

async fn run(
    State(state): State<AppState>,
    Json(body): Json<ScoreRunRequest>,
) -> Result<(StatusCode, Json<ScoreRunResponse>), ApiError> {
    let limit = body.limit.clamp(1, 500);
    let stale_hours = body.stale_hours.clamp(1, 24 * 30);
    let score_stats = run_score(&state.db, limit, stale_hours, body.rescore_all)
        .await
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;
    Ok((
        StatusCode::OK,
        Json(ScoreRunResponse {
            scored: score_stats.scored,
            failed: score_stats.failed,
        }),
    ))
}
