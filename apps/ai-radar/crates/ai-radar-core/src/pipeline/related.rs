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

/// Why the related list is empty (console copy hints — **T-257**).
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RelatedEmptyReason {
    /// Item has no row in `item_embeddings`.
    NoEmbedding,
    /// Neighbors exist but all cosine scores are below `min_similarity`.
    BelowThreshold,
    /// No other embeddings in the candidate pool (low global coverage).
    InsufficientPool,
}

/// Related neighbors for one extracted item.
#[derive(Debug, Clone, serde::Serialize)]
pub struct RelatedResult {
    pub items: Vec<SearchHit>,
    pub count: usize,
    pub has_embedding: bool,
    pub same_category: bool,
    pub min_similarity: f32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub empty_reason: Option<RelatedEmptyReason>,
    /// Highest cosine to any other candidate (even when below threshold).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub best_similarity: Option<f32>,
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
/// Clamp operator-provided similarity floor to a sane range.
#[must_use]
pub fn clamp_min_similarity(min_similarity: f32) -> f32 {
    min_similarity.clamp(0.0, 1.0)
}

pub async fn run_related(
    db: &Database,
    config: &AppConfig,
    extracted_item_id: Uuid,
    limit: i64,
    same_category: bool,
    min_similarity: f32,
) -> anyhow::Result<RelatedResult> {
    let limit = limit.clamp(1, 20);
    let min_similarity = clamp_min_similarity(min_similarity);
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
            same_category,
            min_similarity,
            empty_reason: Some(RelatedEmptyReason::NoEmbedding),
            best_similarity: None,
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

    let mut best_similarity: Option<f32> = None;
    let mut ranked: Vec<(Uuid, f32)> = Vec::new();

    for row in candidates.iter().filter(|row| row.extracted_item_id != extracted_item_id) {
        let Some(sim) = cosine_similarity(&source.vector, &row.vector) else {
            continue;
        };
        best_similarity = Some(best_similarity.map_or(sim, |m| m.max(sim)));
        if sim >= min_similarity {
            ranked.push((row.extracted_item_id, sim));
        }
    }
    ranked.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    ranked.truncate(limit as usize);

    if ranked.is_empty() {
        let empty_reason = if candidates.len() <= 1 {
            RelatedEmptyReason::InsufficientPool
        } else {
            RelatedEmptyReason::BelowThreshold
        };
        return Ok(RelatedResult {
            items: Vec::new(),
            count: 0,
            has_embedding: true,
            same_category,
            min_similarity,
            empty_reason: Some(empty_reason),
            best_similarity,
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
        same_category,
        min_similarity,
        empty_reason: None,
        best_similarity,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clamp_min_similarity_bounds() {
        assert_eq!(clamp_min_similarity(-0.1), 0.0);
        assert_eq!(clamp_min_similarity(0.55), 0.55);
        assert_eq!(clamp_min_similarity(1.5), 1.0);
    }
}
