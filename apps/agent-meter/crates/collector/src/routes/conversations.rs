use axum::{
    extract::{Path, State},
    routing::get,
    Json, Router,
};

use crate::app::AppState;
use crate::errors::AppError;
use crate::services::conversation_service;

async fn get_timeline(
    State(state): State<AppState>,
    Path(conversation_id): Path<String>,
) -> Result<Json<crate::models::timeline::ConversationTimeline>, AppError> {
    let timeline = conversation_service::get_conversation_timeline(
        &state.pool,
        &conversation_id,
        Some(1000),
    )
    .await?;
    Ok(Json(timeline))
}

pub fn router() -> Router<AppState> {
    Router::new().route("/conversations/:conversation_id/timeline", get(get_timeline))
}