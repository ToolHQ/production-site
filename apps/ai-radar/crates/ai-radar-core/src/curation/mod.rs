//! Data curation helpers (entity resolution, dedup).

pub mod entity;
pub mod resolve;

pub use entity::{
    names_similar, normalize_tool_name, normalize_url, tool_key_from_github_metadata,
    tool_key_from_new_raw_item, tool_key_from_title_and_url, tool_key_from_url, EntityIdentity,
};
pub use resolve::{reconcile_pending_entities, resolve_entity_for_inserted, EntityResolveStats};
