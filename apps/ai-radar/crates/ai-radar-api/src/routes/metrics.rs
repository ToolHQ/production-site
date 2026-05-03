//! Prometheus scrape endpoint (`GET /metrics`).

use ai_radar_core::metrics as radar_metrics;
use ai_radar_core::repos::RawItemRepository;
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
    (
        [(header::CONTENT_TYPE, "text/plain; version=0.0.4")],
        state.prometheus.render(),
    )
}
