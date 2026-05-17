//! Orchestrate entity assignment after collect / before extract (**T-231**).

use uuid::Uuid;

use crate::curation::entity::{tool_key_from_new_raw_item, EntityIdentity};
use crate::domain::NewRawItem;
use crate::metrics;
use crate::repos::{PgRawItemRepository, RawItemRepository};

/// Counters for entity resolution passes.
#[derive(Debug, Default, Clone, Copy)]
pub struct EntityResolveStats {
    /// Rows confirmed as cluster leaders.
    pub leaders: u64,
    /// Rows marked `skipped` as cross-source duplicates.
    pub duplicates_marked: u64,
}

/// After a successful idempotent insert, assign `tool_key` or mark duplicate.
///
/// # Errors
///
/// Propagates repository errors.
pub async fn resolve_entity_for_inserted(
    raw_repo: &PgRawItemRepository,
    raw_item_id: Uuid,
    item: &NewRawItem,
) -> Result<EntityResolveStats, crate::db::RepoError> {
    let Some(identity) = tool_key_from_new_raw_item(item) else {
        return Ok(EntityResolveStats::default());
    };
    resolve_with_identity(raw_repo, raw_item_id, &identity).await
}

/// Backfill `tool_key` on pending backlog rows without a key.
///
/// # Errors
///
/// Propagates repository errors.
pub async fn reconcile_pending_entities(
    raw_repo: &PgRawItemRepository,
    limit: i64,
) -> Result<EntityResolveStats, crate::db::RepoError> {
    let pending = raw_repo.list_pending_without_tool_key(limit).await?;
    let mut stats = EntityResolveStats::default();
    for row in pending {
        let item = NewRawItem {
            source_id: row.source_id,
            external_id: row.external_id.clone(),
            url: row.url.clone(),
            title: row.title.clone(),
            raw_content: row.raw_content.clone(),
            content_hash: Some(row.content_hash.clone()),
            metadata_json: Some(row.metadata_json.clone()),
            published_at: row.published_at,
        };
        let Some(identity) = tool_key_from_new_raw_item(&item) else {
            continue;
        };
        let chunk = resolve_with_identity(raw_repo, row.id, &identity).await?;
        stats.leaders += chunk.leaders;
        stats.duplicates_marked += chunk.duplicates_marked;
    }
    Ok(stats)
}

async fn resolve_with_identity(
    raw_repo: &PgRawItemRepository,
    raw_item_id: Uuid,
    identity: &EntityIdentity,
) -> Result<EntityResolveStats, crate::db::RepoError> {
    if let Some(leader) = raw_repo.find_leader_for_tool_key(&identity.tool_key).await? {
        if leader.id == raw_item_id {
            raw_repo
                .assign_entity(raw_item_id, &identity.tool_key, &identity.canonical_url)
                .await?;
            return Ok(EntityResolveStats {
                leaders: 1,
                ..EntityResolveStats::default()
            });
        }

        raw_repo
            .mark_cross_source_duplicate(
                raw_item_id,
                leader.id,
                &identity.tool_key,
                &identity.canonical_url,
            )
            .await?;
        metrics::record_entity_duplicate_skipped();
        return Ok(EntityResolveStats {
            duplicates_marked: 1,
            ..EntityResolveStats::default()
        });
    }

    raw_repo
        .assign_entity(raw_item_id, &identity.tool_key, &identity.canonical_url)
        .await?;
    Ok(EntityResolveStats {
        leaders: 1,
        ..EntityResolveStats::default()
    })
}
