//! Application state shared across handlers.
//!
//! Wraps the database pool plus the repositories handlers can use. Cheap
//! to clone (everything inside is `Arc`-internal at the `SQLx` layer).

use std::sync::Arc;

use ai_radar_core::config::AppConfig;
use ai_radar_core::db::Database;
use ai_radar_core::repos::{
    PgDigestRepository, PgExtractedItemRepository, PgFeedbackRepository, PgRawItemRepository,
    PgScoreRepository, PgSourceRepository,
};
use metrics_exporter_prometheus::PrometheusHandle;

use crate::metrics_cache::{MetricsGaugeCache, METRICS_GAUGE_TTL};

/// Shared application state. Use `Arc<AppState>` if you need cheap
/// cloning across async tasks.
///
/// Some repository handles are wired in already even though no route
/// uses them yet (raw items, scores, feedback, digests). They land
/// with the corresponding epics (T-161..T-170). The `dead_code`
/// allowance keeps the structure self-documenting without warnings.
#[derive(Clone)]
#[allow(dead_code)]
pub struct AppState {
    /// Process configuration (LLM toggles, bind address, …).
    pub config: Arc<AppConfig>,
    /// Prometheus text renderer (`GET /metrics`).
    pub prometheus: PrometheusHandle,
    /// Database pool wrapper.
    pub db: Database,
    /// `sources` repository.
    pub sources: Arc<PgSourceRepository>,
    /// `raw_items` repository.
    pub raw_items: Arc<PgRawItemRepository>,
    /// `extracted_items` repository.
    pub extracted_items: Arc<PgExtractedItemRepository>,
    /// `scores` repository.
    pub scores: Arc<PgScoreRepository>,
    /// `feedback` repository.
    pub feedback: Arc<PgFeedbackRepository>,
    /// `digests` repository.
    pub digests: Arc<PgDigestRepository>,
    /// Cached DB gauge refresh for `/metrics` (**T-263**).
    pub metrics_gauge_cache: Arc<MetricsGaugeCache>,
}

impl AppState {
    /// Build a fresh state from a [`Database`] and Prometheus handle.
    #[must_use]
    pub fn new(db: Database, prometheus: PrometheusHandle, config: Arc<AppConfig>) -> Self {
        Self {
            config,
            prometheus,
            sources: Arc::new(PgSourceRepository::new(&db)),
            raw_items: Arc::new(PgRawItemRepository::new(&db)),
            extracted_items: Arc::new(PgExtractedItemRepository::new(&db)),
            scores: Arc::new(PgScoreRepository::new(&db)),
            feedback: Arc::new(PgFeedbackRepository::new(&db)),
            digests: Arc::new(PgDigestRepository::new(&db)),
            metrics_gauge_cache: Arc::new(MetricsGaugeCache::new(METRICS_GAUGE_TTL)),
            db,
        }
    }
}
