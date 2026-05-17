//! `POST /compare` — category comparison matrix (**T-168**).

use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::post;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use ai_radar_core::pipeline::compare::run_compare;

use crate::error::ApiError;
use crate::state::AppState;

fn default_top_n() -> usize {
    5
}

/// JSON body for `POST /compare`.
#[derive(Debug, Deserialize)]
pub struct CompareRequest {
    /// Category label (exact; never mixes categories).
    pub category: String,
    /// Max tools in the matrix.
    #[serde(default = "default_top_n")]
    pub top_n: usize,
}

/// JSON response for `POST /compare`.
#[derive(Debug, Serialize)]
pub struct CompareResponse {
    /// Persisted comparison id.
    pub id: Uuid,
    /// Category compared.
    pub category: String,
    /// Requested top-N.
    pub top_n: i32,
    /// Rendered Markdown table.
    pub markdown: String,
}

/// Mount `/compare`.
pub fn router() -> Router<AppState> {
    Router::new().route("/compare", post(run))
}

async fn run(
    State(state): State<AppState>,
    Json(body): Json<CompareRequest>,
) -> Result<(StatusCode, Json<CompareResponse>), ApiError> {
    let top_n = body.top_n.clamp(1, 50);
    let result = run_compare(&state.db, body.category.trim(), top_n)
        .await
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;
    Ok((
        StatusCode::OK,
        Json(CompareResponse {
            id: result.comparison.id,
            category: result.comparison.category,
            top_n: result.comparison.top_n,
            markdown: result.markdown,
        }),
    ))
}
