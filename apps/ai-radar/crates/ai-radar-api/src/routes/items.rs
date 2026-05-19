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
use ai_radar_core::pipeline::related::run_related;
use ai_radar_core::pipeline::reprocess::{run_reprocess, ReprocessStage};
use ai_radar_core::pipeline::search::SearchHit;
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
    /// Filter `metadata_json.adoption.velocity_tier` (`spike`, `growing`, …).
    pub velocity_tier: Option<String>,
    /// Filter `metadata_json.source_health.tier` (`healthy`, `noisy`, …).
    pub source_health_tier: Option<String>,
    /// When `false`, only scored items missing an embedding for `EMBEDDING_MODEL` (**T-262**).
    pub has_embedding: Option<bool>,
    #[serde(default)]
    pub sort: String,
}

fn default_limit() -> i64 {
    50
}

/// Resolve embedding model + optional `has_embedding` filter for explorer list (**T-262**).
fn embedding_list_filters(
    config: &ai_radar_core::config::AppConfig,
    has_embedding: Option<bool>,
) -> (Option<String>, Option<bool>) {
    if !config.embeddings_enabled {
        return (None, None);
    }
    let model = config
        .embedding_model
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string);
    let filter = has_embedding.and_then(|want| model.as_ref().map(|_| want));
    (model, filter)
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

#[derive(Debug, Deserialize)]
pub struct RelatedQuery {
    #[serde(default = "default_related_limit")]
    pub limit: i64,
    #[serde(default = "default_same_category")]
    pub same_category: bool,
    #[serde(default = "default_min_similarity")]
    pub min_similarity: f32,
}

fn default_related_limit() -> i64 {
    5
}

fn default_same_category() -> bool {
    true
}

fn default_min_similarity() -> f32 {
    ai_radar_core::pipeline::related::MIN_RELATED_SIMILARITY
}

#[derive(Debug, Serialize)]
pub struct RelatedResponse {
    pub items: Vec<SearchHit>,
    pub count: usize,
    pub has_embedding: bool,
    pub same_category: bool,
    pub min_similarity: f32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub empty_reason: Option<ai_radar_core::pipeline::related::RelatedEmptyReason>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub best_similarity: Option<f32>,
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/items", get(list))
        .route("/items/:id", get(get_one))
        .route("/items/:id/related", get(list_related))
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
    let velocity_tier = q
        .velocity_tier
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let source_health_tier = q
        .source_health_tier
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let sort = ScoredItemSort::parse(&q.sort).map_err(ApiError::BadRequest)?;
    let (embedding_model, has_embedding_filter) = embedding_list_filters(&state.config, q.has_embedding);

    let total = state
        .scores
        .count_scored_items(
            decision,
            category,
            stars_tier,
            quality_warn,
            velocity_tier,
            source_health_tier,
            embedding_model.as_deref(),
            has_embedding_filter,
        )
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
            velocity_tier,
            source_health_tier,
            embedding_model.as_deref(),
            has_embedding_filter,
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

async fn list_related(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Query(q): Query<RelatedQuery>,
) -> Result<(StatusCode, Json<RelatedResponse>), ApiError> {
    state.extracted_items.get(id).await?;

    let result = run_related(
        &state.db,
        &state.config,
        id,
        q.limit,
        q.same_category,
        q.min_similarity,
    )
    .await
    .map_err(|e| ApiError::BadRequest(e.to_string()))?;

    Ok((
        StatusCode::OK,
        Json(RelatedResponse {
            count: result.count,
            has_embedding: result.has_embedding,
            items: result.items,
            same_category: result.same_category,
            min_similarity: result.min_similarity,
            empty_reason: result.empty_reason,
            best_similarity: result.best_similarity,
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

#[cfg(test)]
mod related_query_tests {
    use super::*;

    #[test]
    fn related_query_same_category_false_and_min_similarity() {
        let q: RelatedQuery =
            serde_json::from_str(r#"{"same_category":false,"min_similarity":0.4,"limit":10}"#)
                .expect("deserialize");
        assert!(!q.same_category);
        assert_eq!(q.limit, 10);
        assert!((q.min_similarity - 0.4).abs() < f32::EPSILON);
    }

    #[test]
    fn list_items_query_has_embedding_filter() {
        let q: ListItemsQuery =
            serde_json::from_str(r#"{"has_embedding":false,"limit":10}"#).expect("deserialize");
        assert_eq!(q.has_embedding, Some(false));
    }

    #[test]
    fn related_query_defaults_match_pipeline() {
        let q: RelatedQuery = serde_json::from_str("{}").expect("deserialize");
        assert!(q.same_category);
        assert_eq!(q.limit, 5);
        assert!(
            (q.min_similarity - ai_radar_core::pipeline::related::MIN_RELATED_SIMILARITY).abs()
                < f32::EPSILON
        );
    }
}
