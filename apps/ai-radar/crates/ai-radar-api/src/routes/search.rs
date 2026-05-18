//! `GET /search` — semantic / lexical tool search (**T-249**).

use axum::extract::{Query, State};
use axum::http::StatusCode;
use axum::routing::get;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use ai_radar_core::embedding::build_embedding_provider;
use ai_radar_core::pipeline::search::{run_search, SearchHit, SearchResult};

use crate::error::ApiError;
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct SearchQuery {
    /// Natural-language or keyword query (required).
    pub q: String,
    #[serde(default = "default_limit")]
    pub limit: i64,
    pub category: Option<String>,
}

fn default_limit() -> i64 {
    20
}

#[derive(Debug, Serialize)]
pub struct SearchResponse {
    pub items: Vec<SearchHit>,
    pub mode: &'static str,
    pub query: String,
    pub count: usize,
}

pub fn router() -> Router<AppState> {
    Router::new().route("/search", get(handler))
}

async fn handler(
    State(state): State<AppState>,
    Query(q): Query<SearchQuery>,
) -> Result<(StatusCode, Json<SearchResponse>), ApiError> {
    let query = q.q.trim();
    if query.is_empty() {
        return Err(ApiError::BadRequest("q is required".into()));
    }
    let limit = q.limit.clamp(1, 50);
    let category = q.category.as_deref().map(str::trim).filter(|s| !s.is_empty());

    let embedder = build_embedding_provider(&state.config);
    let SearchResult {
        items,
        mode,
        query: normalized,
    } = run_search(&state.db, &state.config, embedder, query, limit, category)
        .await
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;

    Ok((
        StatusCode::OK,
        Json(SearchResponse {
            count: items.len(),
            items,
            mode,
            query: normalized,
        }),
    ))
}
