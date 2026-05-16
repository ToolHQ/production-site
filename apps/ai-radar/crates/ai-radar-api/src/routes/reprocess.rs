//! `POST /items/:id/reprocess` — manual extract/score rerun (**T-173**).

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::routing::post;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use ai_radar_core::llm::build_llm_provider;
use ai_radar_core::pipeline::reprocess::{run_reprocess, ReprocessStage};

use ai_radar_core::db::RepoError;
use ai_radar_core::repos::{ExtractedItemRepository, PgExtractedItemRepository};

use crate::error::ApiError;
use crate::state::AppState;

/// JSON body for `POST /items/:id/reprocess`.
#[derive(Debug, Deserialize)]
pub struct ReprocessRequest {
    /// `extract`, `score`, or `all`.
    pub stage: String,
}

/// JSON response.
#[derive(Debug, Serialize)]
pub struct ReprocessResponse {
    pub extracted_item_id: Uuid,
    pub raw_item_id: Uuid,
    pub latest_extracted_item_id: Option<Uuid>,
    pub latest_version: Option<i32>,
    pub scored: bool,
}

/// Mount `/items` routes.
pub fn router() -> Router<AppState> {
    Router::new().route("/items/:id/reprocess", post(run))
}

async fn run(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Json(body): Json<ReprocessRequest>,
) -> Result<(StatusCode, Json<ReprocessResponse>), ApiError> {
    let stage =
        ReprocessStage::parse(&body.stage).map_err(|e| ApiError::BadRequest(e.to_string()))?;

    PgExtractedItemRepository::new(&state.db)
        .get(id)
        .await
        .map_err(|e| match e {
            RepoError::NotFound => ApiError::Repo(RepoError::NotFound),
            other => ApiError::BadRequest(other.to_string()),
        })?;

    let llm = build_llm_provider(&state.config);
    let out = run_reprocess(&state.db, &state.config, llm, id, stage)
        .await
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;
    Ok((
        StatusCode::OK,
        Json(ReprocessResponse {
            extracted_item_id: out.extracted_item_id,
            raw_item_id: out.raw_item_id,
            latest_extracted_item_id: out.latest_extracted_item_id,
            latest_version: out.latest_version,
            scored: out.scored,
        }),
    ))
}
