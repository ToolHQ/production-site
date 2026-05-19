//! `GET /models/catalog` — OpenRouter model/pricing diff (**T-270**).

use axum::extract::{Query, State};
use axum::routing::get;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use ai_radar_core::domain::model_catalog::PROVIDER_OPENROUTER;
use ai_radar_core::repos::{ModelCatalogRepository, PgModelCatalogRepository};

use crate::error::ApiError;
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct CatalogQuery {
    #[serde(default = "default_limit")]
    pub limit: i64,
}

fn default_limit() -> i64 {
    20
}

#[derive(Debug, Serialize)]
pub struct CatalogResponse {
    pub last_run: Option<ai_radar_core::domain::model_catalog::ModelCatalogRunSummary>,
    pub events: Vec<ai_radar_core::domain::model_catalog::ModelCatalogEventRow>,
    pub count: usize,
}

pub fn router() -> Router<AppState> {
    Router::new().route("/models/catalog", get(handler))
}

async fn handler(
    State(state): State<AppState>,
    Query(q): Query<CatalogQuery>,
) -> Result<Json<CatalogResponse>, ApiError> {
    let limit = q.limit.clamp(1, 100);
    let repo = PgModelCatalogRepository::new(&state.db);
    let last_run = repo.latest_run(PROVIDER_OPENROUTER).await.map_err(ApiError::from_repo)?;
    let events = repo
        .list_recent_events(PROVIDER_OPENROUTER, limit)
        .await
        .map_err(ApiError::from_repo)?;
    let count = events.len();
    Ok(Json(CatalogResponse {
        last_run,
        events,
        count,
    }))
}
