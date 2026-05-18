//! Semantic duplicate pairs report (cosine ≥ threshold) — **T-252**.

use uuid::Uuid;

use crate::config::AppConfig;
use crate::db::Database;
use crate::embedding::cosine_similarity;
use crate::repos::{
    ItemEmbeddingRepository, PgItemEmbeddingRepository, PgScoreRepository, ScoreRepository,
};

/// Max embeddings scanned per report (bounds O(n²) work).
const SEMANTIC_DUP_POOL: i64 = 300;

/// Default cosine threshold (T-252).
pub const DEFAULT_SEMANTIC_DUP_THRESHOLD: f32 = 0.92;

/// One high-similarity pair between two distinct extracted items.
#[derive(Debug, Clone, serde::Serialize)]
pub struct SemanticDuplicatePair {
    pub extracted_item_id_a: Uuid,
    pub extracted_item_id_b: Uuid,
    pub tool_name_a: Option<String>,
    pub tool_name_b: Option<String>,
    pub category_a: Option<String>,
    pub category_b: Option<String>,
    pub similarity: f32,
}

/// Report payload for `GET /reports/semantic-duplicates`.
#[derive(Debug, Clone, serde::Serialize)]
pub struct SemanticDuplicatesReport {
    pub pairs: Vec<SemanticDuplicatePair>,
    pub count: usize,
    pub threshold: f32,
    pub scanned: usize,
}

fn embedding_model_id(config: &AppConfig) -> Option<String> {
    config
        .embedding_model
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

/// Find semantic near-duplicate pairs above `threshold`.
///
/// Operational report only — does not mutate pipeline state.
///
/// # Errors
///
/// Propagates database errors. Returns empty report when embeddings/model are unavailable.
pub async fn run_semantic_duplicates_report(
    db: &Database,
    config: &AppConfig,
    threshold: f32,
    limit: i64,
) -> anyhow::Result<SemanticDuplicatesReport> {
    let threshold = threshold.clamp(0.5, 0.999);
    let limit = limit.clamp(1, 100);

    let Some(model) = embedding_model_id(config) else {
        return Ok(SemanticDuplicatesReport {
            pairs: Vec::new(),
            count: 0,
            threshold,
            scanned: 0,
        });
    };

    let embeddings = PgItemEmbeddingRepository::new(db);
    let rows = embeddings
        .list_for_search(&model, SEMANTIC_DUP_POOL, None)
        .await
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    let scanned = rows.len();

    let mut pairs: Vec<(Uuid, Uuid, f32)> = Vec::new();
    for i in 0..rows.len() {
        for j in (i + 1)..rows.len() {
            let Some(sim) = cosine_similarity(&rows[i].vector, &rows[j].vector) else {
                continue;
            };
            if sim >= threshold {
                pairs.push((rows[i].extracted_item_id, rows[j].extracted_item_id, sim));
            }
        }
    }
    pairs.sort_by(|a, b| b.2.partial_cmp(&a.2).unwrap_or(std::cmp::Ordering::Equal));
    pairs.truncate(limit as usize);

    if pairs.is_empty() {
        return Ok(SemanticDuplicatesReport {
            pairs: Vec::new(),
            count: 0,
            threshold,
            scanned,
        });
    }

    let mut ids: Vec<Uuid> = Vec::with_capacity(pairs.len() * 2);
    for (a, b, _) in &pairs {
        ids.push(*a);
        ids.push(*b);
    }
    ids.sort_unstable();
    ids.dedup();

    let scores = PgScoreRepository::new(db);
    let summaries = scores
        .list_scored_summaries_by_ids(&ids)
        .await
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    let by_id: std::collections::HashMap<Uuid, _> = summaries
        .into_iter()
        .map(|s| (s.extracted_item_id, s))
        .collect();

    let out: Vec<SemanticDuplicatePair> = pairs
        .into_iter()
        .filter_map(|(id_a, id_b, similarity)| {
            let a = by_id.get(&id_a)?;
            let b = by_id.get(&id_b)?;
            Some(SemanticDuplicatePair {
                extracted_item_id_a: id_a,
                extracted_item_id_b: id_b,
                tool_name_a: a.tool_name.clone(),
                tool_name_b: b.tool_name.clone(),
                category_a: a.category.clone(),
                category_b: b.category.clone(),
                similarity,
            })
        })
        .collect();

    let count = out.len();
    Ok(SemanticDuplicatesReport {
        pairs: out,
        count,
        threshold,
        scanned,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_threshold_is_high_precision() {
        assert!((DEFAULT_SEMANTIC_DUP_THRESHOLD - 0.92).abs() < f32::EPSILON);
    }
}
