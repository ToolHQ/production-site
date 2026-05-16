//! `raw_items` → `extracted_items` via LLM (**T-165**).

use std::sync::Arc;
use std::time::Instant;

use serde_json::json;

use crate::config::AppConfig;
use crate::db::Database;
use crate::domain::RawItemStatus;
use crate::extractor::{extractor_id, llm_extract_with_retry, EXTRACTOR_VERSION};
use crate::llm::LlmProvider;
use crate::metrics;
use crate::repos::{
    ExtractedItemRepository, PgExtractedItemRepository, PgRawItemRepository, RawItemRepository,
};

/// Counters printed by the CLI / API.
#[derive(Debug, Default, Clone, Copy)]
pub struct ExtractStats {
    /// Rows successfully extracted.
    pub extracted: u64,
    /// Rows marked `failed` after LLM/parse errors.
    pub failed: u64,
}

/// Run up to `limit` pending items through the extractor (sequential, concurrency = 1).
///
/// # Errors
///
/// Returns when configuration forbids extract (`LLM_ENABLED=false`) or the database layer fails.
pub async fn run_extract(
    db: &Database,
    config: &AppConfig,
    llm: Arc<dyn LlmProvider>,
    limit: i64,
) -> anyhow::Result<ExtractStats> {
    if !config.llm_enabled {
        anyhow::bail!("LLM_ENABLED must be true for extract (configure LLM_API_KEY and LLM_MODEL)");
    }

    let started = Instant::now();
    let raw_repo = PgRawItemRepository::new(db);
    let extracted_repo = PgExtractedItemRepository::new(db);

    let reconciled = raw_repo.reconcile_extracting_status().await?;
    if reconciled > 0 {
        tracing::info!(
            reconciled,
            "reconciled raw_items stuck in extracting before claim"
        );
    }

    let batch = raw_repo.claim_pending_batch(limit).await?;
    let mut stats = ExtractStats::default();

    for raw in batch {
        match process_one(&raw_repo, &extracted_repo, &llm, &raw).await {
            Ok(()) => stats.extracted += 1,
            Err(e) => {
                tracing::warn!(raw_item_id = %raw.id, error = %e, "extract failed");
                stats.failed += 1;
            }
        }
    }

    metrics::record_extract_pass(stats.extracted, stats.failed, started.elapsed());
    Ok(stats)
}

/// Extract a single raw item by id (used by reprocess; does not use batch claim).
///
/// # Errors
///
/// Same as [`process_one`] — LLM/DB failures propagate.
pub async fn extract_single_raw_item(
    db: &Database,
    config: &AppConfig,
    llm: Arc<dyn LlmProvider>,
    raw_item_id: uuid::Uuid,
) -> anyhow::Result<()> {
    if !config.llm_enabled {
        anyhow::bail!("LLM_ENABLED must be true for extract (configure LLM_API_KEY and LLM_MODEL)");
    }
    let raw_repo = PgRawItemRepository::new(db);
    let extracted_repo = PgExtractedItemRepository::new(db);
    raw_repo
        .mark_status(raw_item_id, crate::domain::RawItemStatus::Pending)
        .await
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    let raw = raw_repo
        .get(raw_item_id)
        .await
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    process_one(&raw_repo, &extracted_repo, &llm, &raw).await
}

async fn process_one(
    raw_repo: &PgRawItemRepository,
    extracted_repo: &PgExtractedItemRepository,
    llm: &Arc<dyn LlmProvider>,
    raw: &crate::domain::RawItem,
) -> anyhow::Result<()> {
    let mut audits = Vec::new();

    let outcome = llm_extract_with_retry(llm, raw, &mut audits).await;

    match outcome {
        Ok((fields, resp)) => {
            let mut new_item =
                fields.into_new_extracted_item(raw.id, extractor_id(), EXTRACTOR_VERSION, &resp);
            if let Some(serde_json::Value::Object(map)) = &mut new_item.metadata_json {
                map.insert("extract_attempts".to_string(), json!(audits));
            }

            extracted_repo.insert(&new_item).await?;
            raw_repo
                .mark_status(raw.id, RawItemStatus::Extracted)
                .await?;
            Ok(())
        }
        Err(e) => {
            for a in &audits {
                raw_repo.append_extract_attempt(raw.id, a.clone()).await?;
            }
            raw_repo.mark_status(raw.id, RawItemStatus::Failed).await?;
            Err(anyhow::anyhow!("{e}"))
        }
    }
}
