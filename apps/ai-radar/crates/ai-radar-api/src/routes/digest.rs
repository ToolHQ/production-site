//! `POST /digest/run` — generate a digest (**T-169**).

use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::post;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use ai_radar_core::pipeline::digest::{run_digest, DigestKind, DigestLimits};

use crate::error::ApiError;
use crate::state::AppState;

fn default_kind() -> String {
    "weekly".into()
}

#[derive(Debug, Deserialize)]
pub struct DigestRunRequest {
    /// `daily` or `weekly`.
    #[serde(default = "default_kind")]
    pub kind: String,
}

#[derive(Debug, Serialize)]
pub struct DigestRunResponse {
    pub digest_id: Uuid,
}

pub fn router() -> Router<AppState> {
    Router::new().route("/digest/run", post(run))
}

async fn run(
    State(state): State<AppState>,
    Json(body): Json<DigestRunRequest>,
) -> Result<(StatusCode, Json<DigestRunResponse>), ApiError> {
    let kind = match body.kind.trim() {
        "daily" => DigestKind::Daily,
        "weekly" => DigestKind::Weekly,
        other => {
            return Err(ApiError::BadRequest(format!(
                "invalid kind {other:?}, expected 'daily' or 'weekly'"
            )));
        }
    };

    let digest_id = run_digest(&state.db, kind, DigestLimits::default())
        .await
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;

    Ok((StatusCode::OK, Json(DigestRunResponse { digest_id })))
}
