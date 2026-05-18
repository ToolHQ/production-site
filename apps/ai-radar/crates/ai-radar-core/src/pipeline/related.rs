//! Related items by embedding neighborhood (**T-251**).

use std::collections::HashMap;

use uuid::Uuid;

use crate::config::AppConfig;
use crate::db::Database;
use crate::embedding::cosine_similarity;
use crate::pipeline::search::SearchHit;
use crate::repos::{
    ExtractedItemRepository, ItemEmbeddingRepository, PgExtractedItemRepository,
    PgItemEmbeddingRepository, PgScoreRepository, ScoreRepository,
};

/// Candidate pool for related-item ranking.
const RELATED_CANDIDATE_POOL: i64 = 250;

/// Minimum cosine similarity to surface a neighbor.
pub const MIN_RELATED_SIMILARITY: f32 = 0.55;

/// Related neighbors for one extracted item.
#[derive(Debug, Clone, serde::Serialize)]
pub struct RelatedResult {
    pub items: Vec<SearchHit>,
    pub count: usize,
    pub has_embedding: bool,
}

fn embedding_model_id(config: &AppConfig) -> Option<String> {
    config
        .embedding_model
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

/// Top-k scored items similar to `extracted_item_id` (excludes self).
///
/// Returns an empty list when the item has no stored embedding.
///
/// # Errors
///
/// Propagates database errors.
pub async fn run_related(
    db: &Database,
    config: &AppConfig,
    extracted_item_id: Uuid,
    limit: i64,
    same_category: bool,
) -> anyhow::Result<RelatedResult> {
    let limit = limit.clamp(1, 20);
    let embeddings = PgItemEmbeddingRepository::new(db);
    let source = embeddings
        .get_latest(extracted_item_id)
        .await
        .map_err(|e| anyhow::anyhow!("{e}"))?;

    let Some(source) = source else {
        return Ok(RelatedResult {
            items: Vec::new(),
            count: 0,
            has_embedding: false,
        });
    };

    let model = embedding_model_id(config).unwrap_or_else(|| source.model.clone());
    let category: Option<String> = if same_category {
        let extracted = PgExtractedItemRepository::new(db);
        let row = extracted.get(extracted_item_id).await.map_err(|e| anyhow::anyhow!("{e}"))?;
        row.category
            .map(|c| c.trim().to_string())
            .filter(|s| !s.is_empty())
    } else {
        None
    };

    let candidates = embeddings
        .list_for_search(&model, RELATED_CANDIDATE_POOL, category.as_deref())
        .await
        .map_err(|e| anyhow::anyhow!("{e}"))?;

    let mut ranked: Vec<(Uuid, f32)> = candidates
        .iter()
        .filter(|row| row.extracted_item_id != extracted_item_id)
        .filter_map(|row| {
            cosine_similarity(&source.vector, &row.vector)
                .filter(|&sim| sim >= MIN_RELATED_SIMILARITY)
                .map(|sim| (row.extracted_item_id, sim))
        })
        .collect();
    ranked.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    ranked.truncate(limit as usize);

    if ranked.is_empty() {
        return Ok(RelatedResult {
            items: Vec::new(),
            count: 0,
            has_embedding: true,
        });
    }

    let ids: Vec<Uuid> = ranked.iter().map(|(id, _)| *id).collect();
    let sim_by_id: HashMap<Uuid, f32> = ranked.into_iter().collect();

    let scores = PgScoreRepository::new(db);
    let summaries = scores
        .list_scored_summaries_by_ids(&ids)
        .await
        .map_err(|e| anyhow::anyhow!("{e}"))?;

    let mut items: Vec<SearchHit> = summaries
        .into_iter()
        .filter_map(|item| {
            sim_by_id
                .get(&item.extracted_item_id)
                .map(|&similarity| SearchHit { item, similarity })
        })
        .collect();
    items.sort_by(|a, b| {
        b.similarity
            .partial_cmp(&a.similarity)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let count = items.len();
    Ok(RelatedResult {
        items,
        count,
        has_embedding: true,
    })
}
