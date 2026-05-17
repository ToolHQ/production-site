//! `POST /compare` — category comparison matrix (**T-168**).

use axum::extract::State;
use axum::http::StatusCode;
use axum::extract::Query;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use ai_radar_core::pipeline::compare::run_compare;
use ai_radar_core::repos::{ComparisonRepository, PgComparisonRepository};

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

/// Query params for `GET /comparisons`.
#[derive(Debug, Deserialize)]
pub struct ListComparisonsQuery {
    pub category: Option<String>,
    #[serde(default = "default_list_limit")]
    pub limit: i64,
}

fn default_list_limit() -> i64 {
    10
}

/// JSON envelope for `GET /comparisons`.
#[derive(Debug, Serialize)]
pub struct ListComparisonsResponse {
    pub items: Vec<ComparisonSummary>,
    pub count: usize,
}

/// Lightweight comparison row for the console.
#[derive(Debug, Serialize)]
pub struct ComparisonSummary {
    pub id: Uuid,
    pub category: String,
    pub top_n: i32,
    pub generated_at: String,
}

/// Mount `/compare` and `/comparisons`.
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/compare", post(run))
        .route("/comparisons", get(list_recent))
}

async fn list_recent(
    State(state): State<AppState>,
    Query(q): Query<ListComparisonsQuery>,
) -> Result<Json<ListComparisonsResponse>, ApiError> {
    let repo = PgComparisonRepository::new(&state.db);
    let limit = q.limit.clamp(1, 50);
    let items = repo
        .list_recent(q.category.as_deref(), limit)
        .await?
        .into_iter()
        .map(|c| ComparisonSummary {
            id: c.id,
            category: c.category,
            top_n: c.top_n,
            generated_at: c.generated_at.to_rfc3339(),
        })
        .collect::<Vec<_>>();
    let count = items.len();
    Ok(Json(ListComparisonsResponse { items, count }))
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
