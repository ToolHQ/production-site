//! `GET /items`, `GET /items/:id`, and `POST /items/:id/reprocess` (**T-177**, **T-173**).

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use ai_radar_core::domain::{
    ExtractedItem, Feedback, FeedbackType, NewFeedback, RawItem, Score, ScoredItemSummary,
};
use ai_radar_core::llm::build_llm_provider;
use ai_radar_core::pipeline::reprocess::{run_reprocess, ReprocessStage};
use ai_radar_core::repos::{
    ExtractedItemRepository, FeedbackRepository, RawItemRepository, ScoreRepository,
    ScoredItemSort,
};

use ai_radar_core::db::RepoError;
use crate::error::ApiError;
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct ListItemsQuery {
    #[serde(default = "default_limit")]
    pub limit: i64,
    #[serde(default)]
    pub offset: i64,
    pub decision: Option<String>,
    pub category: Option<String>,
    /// Filter `metadata_json.adoption.stars_tier` (`niche`, `growing`, `popular`, `viral`).
    pub stars_tier: Option<String>,
    /// When `true`, only rows with `quality_warn` in extract metadata.
    pub quality_warn: Option<bool>,
    #[serde(default)]
    pub sort: String,
}

fn default_limit() -> i64 {
    50
}

#[derive(Debug, Serialize)]
pub struct ItemListResponse {
    pub items: Vec<ScoredItemSummary>,
    pub count: usize,
    pub total: i64,
    pub limit: i64,
    pub offset: i64,
}

#[derive(Debug, Serialize)]
pub struct ItemDetailResponse {
    pub extracted: ExtractedItem,
    pub raw: RawItem,
    pub latest_score: Score,
    pub scores: Vec<Score>,
    pub feedbacks: Vec<Feedback>,
}

#[derive(Debug, Deserialize)]
pub struct CreateFeedbackRequest {
    pub feedback_type: String,
    pub notes: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct CreateFeedbackResponse {
    pub feedback: Feedback,
}

#[derive(Debug, Deserialize)]
pub struct ReprocessRequest {
    pub stage: String,
}

#[derive(Debug, Serialize)]
pub struct ReprocessResponse {
    pub extracted_item_id: Uuid,
    pub raw_item_id: Uuid,
    pub latest_extracted_item_id: Option<Uuid>,
    pub latest_version: Option<i32>,
    pub scored: bool,
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/items", get(list))
        .route("/items/:id", get(get_one))
        .route("/items/:id/feedback", post(create_feedback))
        .route("/items/:id/reprocess", post(reprocess))
}

async fn list(
    State(state): State<AppState>,
    Query(q): Query<ListItemsQuery>,
) -> Result<(StatusCode, Json<ItemListResponse>), ApiError> {
    let limit = q.limit.clamp(1, 100);
    let offset = q.offset.max(0);
    let decision = q.decision.as_deref().map(str::trim).filter(|s| !s.is_empty());
    let category = q.category.as_deref().map(str::trim).filter(|s| !s.is_empty());
    let stars_tier = q.stars_tier.as_deref().map(str::trim).filter(|s| !s.is_empty());
    let quality_warn = q.quality_warn;
    let sort = ScoredItemSort::parse(&q.sort).map_err(ApiError::BadRequest)?;

    let total = state
        .scores
        .count_scored_items(decision, category, stars_tier, quality_warn)
        .await
        .map_err(ApiError::from)?;

    let items = state
        .scores
        .list_scored_items(
            limit,
            offset,
            decision,
            category,
            stars_tier,
            quality_warn,
            sort,
        )
        .await
        .map_err(ApiError::from)?;

    Ok((
        StatusCode::OK,
        Json(ItemListResponse {
            count: items.len(),
            total,
            limit,
            offset,
            items,
        }),
    ))
}

async fn get_one(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<(StatusCode, Json<ItemDetailResponse>), ApiError> {
    let extracted = state.extracted_items.get(id).await?;
    let raw = state.raw_items.get(extracted.raw_item_id).await?;
    let scores = state.scores.list_for_extracted_item(id).await?;
    let latest_score = scores
        .first()
        .cloned()
        .ok_or(ApiError::Repo(RepoError::NotFound))?;
    let feedbacks = state.feedback.list_for_item(id).await?;

    Ok((
        StatusCode::OK,
        Json(ItemDetailResponse {
            extracted,
            raw,
            latest_score,
            scores,
            feedbacks,
        }),
    ))
}

async fn create_feedback(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Json(body): Json<CreateFeedbackRequest>,
) -> Result<(StatusCode, Json<CreateFeedbackResponse>), ApiError> {
    state.extracted_items.get(id).await?;

    let feedback_type = FeedbackType::parse(body.feedback_type.trim())
        .map_err(|v| ApiError::BadRequest(format!("invalid feedback_type: {v}")))?;

    let notes = body
        .notes
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string);

    let feedback = state
        .feedback
        .insert(&NewFeedback {
            extracted_item_id: id,
            feedback_type,
            notes,
        })
        .await?;

    tracing::info!(
        extracted_item_id = %id,
        feedback_type = %feedback.feedback_type.as_str(),
        "operator feedback recorded"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateFeedbackResponse { feedback }),
    ))
}

async fn reprocess(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Json(body): Json<ReprocessRequest>,
) -> Result<(StatusCode, Json<ReprocessResponse>), ApiError> {
    let stage =
        ReprocessStage::parse(&body.stage).map_err(|e| ApiError::BadRequest(e.to_string()))?;

    state.extracted_items.get(id).await?;

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
