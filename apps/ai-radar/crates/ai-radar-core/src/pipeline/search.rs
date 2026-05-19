//! Semantic and lexical search over scored items (**T-249**).

use std::collections::HashMap;
use std::sync::Arc;

use uuid::Uuid;

use crate::config::AppConfig;
use crate::db::Database;
use crate::domain::ScoredItemSummary;
use crate::embedding::{cosine_similarity, EmbedRequest, EmbeddingProvider};
use crate::metrics;
use crate::repos::{
    ItemEmbeddingRepository, PgItemEmbeddingRepository, PgScoreRepository, ScoreRepository,
};
use crate::util::limits::MAX_EXTRACT_INPUT_CHARS;

/// Candidate pool size before ranking (keeps API latency bounded).
const SEARCH_CANDIDATE_POOL: i64 = 250;

/// One search hit with similarity in \[0, 1\].
#[derive(Debug, Clone, serde::Serialize)]
pub struct SearchHit {
    #[serde(flatten)]
    pub item: ScoredItemSummary,
    /// Cosine similarity (semantic) or lexical overlap score.
    pub similarity: f32,
}

/// Search response metadata.
#[derive(Debug, Clone, serde::Serialize)]
pub struct SearchResult {
    pub items: Vec<SearchHit>,
    /// `semantic` or `lexical`.
    pub mode: &'static str,
    pub query: String,
}

fn embedding_model_id(config: &AppConfig) -> Option<String> {
    config
        .embedding_model
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

fn truncate_query(q: &str) -> String {
    let mut s = q.trim().to_string();
    if s.len() > MAX_EXTRACT_INPUT_CHARS {
        s.truncate(MAX_EXTRACT_INPUT_CHARS);
    }
    s
}

/// Word-overlap score for lexical fallback (0–1).
#[must_use]
pub fn lexical_similarity(query: &str, item: &ScoredItemSummary) -> f32 {
    let q_lower = query.to_lowercase();
    let q_words: Vec<&str> = q_lower
        .split_whitespace()
        .filter(|w| w.len() >= 2)
        .collect();
    if q_words.is_empty() {
        return 0.0;
    }
    let haystack = format!(
        "{} {} {} {}",
        item.tool_name.as_deref().unwrap_or_default(),
        item.category.as_deref().unwrap_or_default(),
        item.summary.as_deref().unwrap_or_default(),
        ""
    )
    .to_lowercase();
    let hits = q_words.iter().filter(|w| haystack.contains(**w)).count();
    hits as f32 / q_words.len() as f32
}

async fn run_lexical(
    scores: &PgScoreRepository,
    query: &str,
    category: Option<&str>,
    limit: i64,
) -> anyhow::Result<SearchResult> {
    let rows = scores
        .search_lexical(query, category, limit)
        .await
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    let items = rows
        .into_iter()
        .map(|item| {
            let similarity = lexical_similarity(query, &item);
            SearchHit { item, similarity }
        })
        .collect();
    metrics::record_search("lexical");
    Ok(SearchResult {
        items,
        mode: "lexical",
        query: query.to_string(),
    })
}

async fn run_semantic(
    db: &Database,
    config: &AppConfig,
    embedder: Arc<dyn EmbeddingProvider>,
    query: &str,
    category: Option<&str>,
    limit: i64,
) -> anyhow::Result<SearchResult> {
    let model = embedding_model_id(config)
        .ok_or_else(|| anyhow::anyhow!("EMBEDDING_MODEL not configured"))?;
    let query_vec = embedder
        .embed(EmbedRequest {
            input: query.to_string(),
        })
        .await
        .map_err(|e| anyhow::anyhow!("embed query: {e}"))?;

    let embeddings = PgItemEmbeddingRepository::new(db);
    let candidates = embeddings
        .list_for_search(&model, SEARCH_CANDIDATE_POOL, category)
        .await
        .map_err(|e| anyhow::anyhow!("{e}"))?;

    let mut ranked: Vec<(Uuid, f32)> = candidates
        .iter()
        .filter_map(|row| {
            cosine_similarity(&query_vec.vector, &row.vector).map(|sim| (row.extracted_item_id, sim))
        })
        .collect();
    ranked.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    ranked.truncate(limit as usize);

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

    metrics::record_search("semantic");
    Ok(SearchResult {
        items,
        mode: "semantic",
        query: query.to_string(),
    })
}

/// Search tools by natural-language query.
///
/// Uses semantic embeddings when enabled; otherwise lexical ILIKE fallback.
///
/// # Errors
///
/// Propagates database and embedding provider failures. On semantic path failure,
/// falls back to lexical search.
pub async fn run_search(
    db: &Database,
    config: &AppConfig,
    embedder: Arc<dyn EmbeddingProvider>,
    query: &str,
    limit: i64,
    category: Option<&str>,
) -> anyhow::Result<SearchResult> {
    let query = truncate_query(query);
    if query.is_empty() {
        anyhow::bail!("search query must not be empty");
    }
    let limit = limit.clamp(1, 50);
    let category = category.map(str::trim).filter(|s| !s.is_empty());

    let scores = PgScoreRepository::new(db);

    if !config.embeddings_enabled {
        return run_lexical(&scores, &query, category, limit).await;
    }

    match run_semantic(db, config, embedder, &query, category, limit).await {
        Ok(result) => Ok(result),
        Err(e) => {
            tracing::warn!(error = %e, "semantic search failed; falling back to lexical");
            run_lexical(&scores, &query, category, limit).await
        }
    }
}

/// Convenience wrapper building the embedding provider from config.
///
/// # Errors
///
/// Same as [`run_search`].
pub async fn run_search_from_config(
    db: &Database,
    config: &AppConfig,
    query: &str,
    limit: i64,
    category: Option<&str>,
) -> anyhow::Result<SearchResult> {
    let embedder = crate::embedding::build_embedding_provider(config);
    run_search(db, config, embedder, query, limit, category).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::{Decision, ScoredItemSummary};
    use chrono::Utc;
    use uuid::Uuid;

    fn sample_item(name: &str, summary: &str) -> ScoredItemSummary {
        ScoredItemSummary {
            extracted_item_id: Uuid::new_v4(),
            tool_name: Some(name.to_string()),
            category: Some("agents".to_string()),
            summary: Some(summary.to_string()),
            score: 0.5,
            decision: Decision::Monitor,
            scored_at: Utc::now(),
            extracted_at: Utc::now(),
            adoption: None,
            quality_warn: None,
            has_embedding: None,
        }
    }

    #[test]
    fn lexical_similarity_matches_words() {
        let item = sample_item("Cursor Agent", "IDE coding assistant");
        let sim = lexical_similarity("cursor coding", &item);
        assert!(sim > 0.5, "expected overlap, got {sim}");
    }

    #[test]
    fn lexical_similarity_empty_query() {
        let item = sample_item("x", "y");
        assert_eq!(lexical_similarity("", &item), 0.0);
    }
}
