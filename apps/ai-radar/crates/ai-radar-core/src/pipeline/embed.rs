//! Embed `extracted_items` after extract (**T-248**).

use std::sync::Arc;
use std::time::Instant;

use crate::config::AppConfig;
use crate::db::Database;
use crate::domain::ExtractedItem;
use crate::embedding::{build_embedding_provider, EmbedRequest, EmbeddingProvider};
use crate::metrics;
use crate::repos::{
    ItemEmbeddingRepository, NewItemEmbedding, PgItemEmbeddingRepository,
};
use crate::util::limits::MAX_EXTRACT_INPUT_CHARS;

/// Counters for CLI / metrics.
#[derive(Debug, Default, Clone, Copy)]
pub struct EmbedStats {
    /// Rows embedded successfully.
    pub embedded: u64,
    /// Provider or persistence failures.
    pub failed: u64,
    /// Rows skipped (empty canonical text).
    pub skipped: u64,
}

/// Build canonical text for embedding from structured extract fields.
#[must_use]
pub fn build_embed_text(item: &ExtractedItem) -> String {
    let mut parts = Vec::new();
    if let Some(name) = item.tool_name.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        parts.push(name.to_string());
    }
    if let Some(cat) = item.category.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        parts.push(format!("Category: {cat}"));
    }
    if let Some(summary) = item.summary.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        parts.push(summary.to_string());
    }
    if let Some(problem) = item
        .problem_solved
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        parts.push(format!("Problem: {problem}"));
    }
    let mut text = parts.join("\n\n");
    if text.len() > MAX_EXTRACT_INPUT_CHARS {
        text.truncate(MAX_EXTRACT_INPUT_CHARS);
    }
    text
}

fn embedding_model_id(config: &AppConfig) -> anyhow::Result<String> {
    config
        .embedding_model
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .ok_or_else(|| {
            anyhow::anyhow!(
                "EMBEDDING_MODEL is required when EMBEDDINGS_ENABLED=true (configure in ai-radar-llm secret)"
            )
        })
}

/// Embed up to `limit` latest extracted items missing vectors for the configured model.
///
/// # Errors
///
/// Returns when embeddings are disabled, model is unset, or the database layer fails.
pub async fn run_embed_batch(
    db: &Database,
    config: &AppConfig,
    embedder: Arc<dyn EmbeddingProvider>,
    limit: i64,
) -> anyhow::Result<EmbedStats> {
    if !config.embeddings_enabled {
        anyhow::bail!(
            "EMBEDDINGS_ENABLED must be true for embed (set EMBEDDING_MODEL and LLM_API_KEY)"
        );
    }
    let model = embedding_model_id(config)?;
    let started = Instant::now();
    let repo = PgItemEmbeddingRepository::new(db);
    let pending = repo
        .list_pending_for_embedding(&model, limit.max(1))
        .await
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    let mut stats = EmbedStats::default();

    for item in pending {
        let text = build_embed_text(&item);
        if text.trim().is_empty() {
            stats.skipped += 1;
            metrics::record_embedding("skipped");
            continue;
        }
        match embedder
            .embed(EmbedRequest { input: text })
            .await
        {
            Ok(resp) => {
                let payload = NewItemEmbedding {
                    extracted_item_id: item.id,
                    model: resp.model,
                    dimensions: i32::try_from(resp.dimensions)
                        .map_err(|_| anyhow::anyhow!("embedding dimension overflow"))?,
                    vector: resp.vector,
                };
                repo.upsert(&payload)
                    .await
                    .map_err(|e| anyhow::anyhow!("{e}"))?;
                stats.embedded += 1;
                metrics::record_embedding("success");
            }
            Err(e) => {
                tracing::warn!(
                    extracted_item_id = %item.id,
                    error = %e,
                    "embed failed"
                );
                stats.failed += 1;
                metrics::record_embedding("failed");
            }
        }
    }

    metrics::record_embed_pass(stats.embedded, stats.failed, stats.skipped, started.elapsed());
    Ok(stats)
}

/// Convenience: build provider from config and run batch.
///
/// # Errors
///
/// Same as [`run_embed_batch`].
pub async fn run_embed_batch_from_config(
    db: &Database,
    config: &AppConfig,
    limit: i64,
) -> anyhow::Result<EmbedStats> {
    let embedder = build_embedding_provider(config);
    run_embed_batch(db, config, embedder, limit).await
}
