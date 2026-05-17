//! Data curation helpers (entity resolution, dedup).

pub mod adoption;
pub mod entity;
pub mod feedback_calibration;
pub mod resolve;
pub mod source_health;
pub mod velocity;

pub use feedback_calibration::{
    apply_feedback_calibration, calibration_delta, CategoryFeedbackStats,
};
pub use entity::{
    names_similar, normalize_tool_name, normalize_url, tool_key_from_github_metadata,
    tool_key_from_new_raw_item, tool_key_from_title_and_url, tool_key_from_url, EntityIdentity,
};
pub use adoption::{
    activity_tier, adoption_from_extracted, adoption_from_raw, stars_tier, ActivityTier,
    AdoptionSnapshot, StarsTier,
};
pub use resolve::{reconcile_pending_entities, resolve_entity_for_inserted, EntityResolveStats};
pub use source_health::{
    health_tier, snapshot_from_counts, source_health_from_extracted, SourceHealthSnapshot,
    SourceHealthTier,
};
pub use velocity::{
    enrich_adoption, record_metrics_snapshot, velocity_for_raw, velocity_tier, VelocitySnapshot,
    VelocityTier, VELOCITY_WINDOW_DAYS,
};
