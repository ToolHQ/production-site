//! `POST /extract/run` — trigger LLM extract pass (**T-165**).

use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::post;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use ai_radar_core::llm::build_llm_provider;
use ai_radar_core::pipeline::extract::run_extract;

use crate::error::ApiError;
use crate::state::AppState;

fn default_extract_limit() -> i64 {
    50
}

/// JSON body for `POST /extract/run`.
#[derive(Debug, Deserialize)]
pub struct ExtractRunRequest {
    /// Max `raw_items` rows to claim in this invocation.
    #[serde(default = "default_extract_limit")]
    pub limit: i64,
}

/// JSON response for `POST /extract/run`.
#[derive(Debug, Serialize)]
pub struct ExtractRunResponse {
    /// Rows successfully extracted.
    pub extracted: u64,
    /// Rows marked `failed`.
    pub failed: u64,
    /// Rows persisted with quality score 40–69.
    pub quality_warn: u64,
    /// Rows rejected by quality gate (score < 40).
    pub quality_rejected: u64,
}

/// Mount `/extract` routes.
pub fn router() -> Router<AppState> {
    Router::new().route("/extract/run", post(run))
}

async fn run(
    State(state): State<AppState>,
    Json(body): Json<ExtractRunRequest>,
) -> Result<(StatusCode, Json<ExtractRunResponse>), ApiError> {
    let limit = body.limit.clamp(1, 500);
    let llm = build_llm_provider(&state.config);
    let extract_stats = run_extract(&state.db, &state.config, llm, limit)
        .await
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;
    Ok((
        StatusCode::OK,
        Json(ExtractRunResponse {
            extracted: extract_stats.extracted,
            failed: extract_stats.failed,
            quality_warn: extract_stats.quality_warn,
            quality_rejected: extract_stats.quality_rejected,
        }),
    ))
}
