//! Prometheus scrape endpoint (`GET /metrics`).

use ai_radar_core::metrics as radar_metrics;
use ai_radar_core::repos::{load_embedding_coverage, RawItemRepository};
use axum::extract::State;
use axum::http::header;
use axum::response::IntoResponse;
use axum::routing::get;
use axum::Router;

use crate::state::AppState;

/// Router exposing Prometheus text exposition format.
pub fn router() -> Router<AppState> {
    Router::new().route("/metrics", get(handler))
}

async fn handler(State(state): State<AppState>) -> impl IntoResponse {
    match state.raw_items.count_pending().await {
        Ok(n) => radar_metrics::set_pending_raw_items_count(n),
        Err(e) => tracing::error!(error = %e, "metrics: count_pending failed"),
    }
    let embed_pending = if state.config.embeddings_enabled {
        state
            .config
            .embedding_model
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(|model| load_embedding_coverage(&state.db, model))
    } else {
        None
    };
    match embed_pending {
        Some(fut) => match fut.await {
            Ok(cov) => {
                radar_metrics::set_embeddings_pending_count(Some(cov.embeddings_pending));
                radar_metrics::set_embeddings_coverage_pct(Some(cov.coverage_pct));
            }
            Err(e) => {
                tracing::error!(error = %e, "metrics: embedding coverage failed");
                radar_metrics::set_embeddings_pending_count(None);
                radar_metrics::set_embeddings_coverage_pct(None);
            }
        },
        None => {
            radar_metrics::set_embeddings_pending_count(None);
            radar_metrics::set_embeddings_coverage_pct(None);
        }
    }
    (
        [(header::CONTENT_TYPE, "text/plain; version=0.0.4")],
        state.prometheus.render(),
    )
}
