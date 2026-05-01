//! Application state shared across handlers.
//!
//! Wraps the database pool plus the repositories handlers can use. Cheap
//! to clone (everything inside is `Arc`-internal at the `SQLx` layer).

use std::sync::Arc;

use ai_radar_core::db::Database;
use ai_radar_core::repos::{
    PgDigestRepository, PgExtractedItemRepository, PgFeedbackRepository, PgRawItemRepository,
    PgScoreRepository, PgSourceRepository,
};

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
}

impl AppState {
    /// Build a fresh state from a [`Database`].
    #[must_use]
    pub fn new(db: Database) -> Self {
        Self {
            sources: Arc::new(PgSourceRepository::new(&db)),
            raw_items: Arc::new(PgRawItemRepository::new(&db)),
            extracted_items: Arc::new(PgExtractedItemRepository::new(&db)),
            scores: Arc::new(PgScoreRepository::new(&db)),
            feedback: Arc::new(PgFeedbackRepository::new(&db)),
            digests: Arc::new(PgDigestRepository::new(&db)),
            db,
        }
    }
}
