//! Prometheus scrape endpoint (`GET /metrics`).

use std::time::{Duration, Instant};

use ai_radar_core::db::RepoError;
use ai_radar_core::metrics as radar_metrics;
use ai_radar_core::repos::{load_embedding_coverage, RawItemRepository};
use axum::extract::State;
use axum::http::header;
use axum::response::IntoResponse;
use axum::routing::get;
use axum::Router;

use crate::metrics_cache::DbGaugeSnapshot;
use crate::state::AppState;

const METRICS_DB_RETRIES: u32 = 2;
const METRICS_DB_RETRY_DELAY: Duration = Duration::from_millis(100);

/// Router exposing Prometheus text exposition format.
pub fn router() -> Router<AppState> {
    Router::new().route("/metrics", get(handler))
}

async fn handler(State(state): State<AppState>) -> impl IntoResponse {
    if let Some(snap) = state.metrics_gauge_cache.fresh().await {
        apply_gauge_snapshot(snap);
    } else if let Some(snap) = refresh_db_gauges(&state).await {
        apply_gauge_snapshot(snap);
    } else if let Some(stale) = state.metrics_gauge_cache.stale().await {
        tracing::warn!(
            event = "metrics.gauge_stale",
            age_secs = stale.refreshed_at.elapsed().as_secs(),
            "metrics: using stale DB gauge snapshot after refresh failure"
        );
        apply_gauge_snapshot(stale);
    } else {
        tracing::error!("metrics: no DB gauge snapshot available");
        radar_metrics::set_pending_raw_items_count(0);
        radar_metrics::set_embeddings_pending_count(None);
        radar_metrics::set_embeddings_coverage_pct(None);
    }

    (
        [(header::CONTENT_TYPE, "text/plain; version=0.0.4")],
        state.prometheus.render(),
    )
}

fn apply_gauge_snapshot(snap: DbGaugeSnapshot) {
    radar_metrics::set_pending_raw_items_count(snap.pending_raw_items);
    radar_metrics::set_embeddings_pending_count(snap.embeddings_pending);
    radar_metrics::set_embeddings_coverage_pct(snap.embeddings_coverage_pct);
}

async fn refresh_db_gauges(state: &AppState) -> Option<DbGaugeSnapshot> {
    let pending = match with_metrics_retry(|| state.raw_items.count_pending()).await {
        Ok(n) => n,
        Err(e) => {
            log_metrics_db_error("count_pending", &e);
            return None;
        }
    };

    let (embeddings_pending, embeddings_coverage_pct) =
        if state.config.embeddings_enabled {
            let model = state
                .config
                .embedding_model
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty());
            match model {
                Some(model) => match with_metrics_retry(|| load_embedding_coverage(&state.db, model)).await
                {
                    Ok(cov) => (
                        Some(cov.embeddings_pending),
                        Some(cov.coverage_pct),
                    ),
                    Err(e) => {
                        log_metrics_db_error("embedding coverage", &e);
                        return None;
                    }
                },
                None => (None, None),
            }
        } else {
            (None, None)
        };

    let snap = DbGaugeSnapshot {
        pending_raw_items: pending,
        embeddings_pending,
        embeddings_coverage_pct,
        refreshed_at: Instant::now(),
    };
    state.metrics_gauge_cache.store(snap).await;
    Some(snap)
}

async fn with_metrics_retry<T, F, Fut>(mut f: F) -> Result<T, RepoError>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<T, RepoError>>,
{
    let mut last = None;
    for attempt in 0..=METRICS_DB_RETRIES {
        match f().await {
            Ok(v) => return Ok(v),
            Err(e) if is_transient_metrics_db_error(&e) && attempt < METRICS_DB_RETRIES => {
                last = Some(e);
                tokio::time::sleep(METRICS_DB_RETRY_DELAY).await;
            }
            Err(e) => return Err(e),
        }
    }
    Err(last.expect("retry loop always returns or sets last"))
}

fn is_transient_metrics_db_error(err: &RepoError) -> bool {
    let msg = err.to_string().to_ascii_lowercase();
    msg.contains("name or service not known")
        || msg.contains("connection refused")
        || msg.contains("connection reset")
        || msg.contains("timeout")
        || msg.contains("pool timed out")
        || msg.contains("communicating with database")
}

fn log_metrics_db_error(stage: &str, err: &RepoError) {
    if is_transient_metrics_db_error(err) {
        tracing::warn!(error = %err, stage, "metrics: transient DB error refreshing gauges");
    } else {
        tracing::error!(error = %err, stage, "metrics: DB error refreshing gauges");
    }
}
