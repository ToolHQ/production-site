//! `raw_items` → `extracted_items` via LLM (**T-165**).

use std::sync::Arc;
use std::time::Instant;

use serde_json::json;

use crate::config::AppConfig;
use crate::db::Database;
use crate::domain::RawItemStatus;
use crate::curation::{
    adoption_from_raw, enrich_adoption, reconcile_pending_entities, velocity_for_raw,
};
use crate::extractor::{
    assess_extract_quality, audit_entry, extractor_id, llm_extract_with_retry, QualityTier,
    EXTRACTOR_VERSION,
};
use crate::llm::LlmProvider;
use crate::metrics;
use crate::repos::{
    ExtractedItemRepository, PgExtractedItemRepository, PgRawItemRepository,
    PgToolMetricsSnapshotRepository, RawItemRepository,
};

/// Counters printed by the CLI / API.
#[derive(Debug, Default, Clone, Copy)]
pub struct ExtractStats {
    /// Rows successfully extracted (pass + warn tiers).
    pub extracted: u64,
    /// Rows marked `failed` after LLM/parse errors.
    pub failed: u64,
    /// Extracted rows with quality score 40–69 (`low_confidence`).
    pub quality_warn: u64,
    /// Rows rejected by quality gate (< 40) before insert.
    pub quality_rejected: u64,
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
    let snapshots = PgToolMetricsSnapshotRepository::new(db);

    let reconciled = raw_repo.reconcile_extracting_status().await?;
    if reconciled > 0 {
        tracing::info!(
            reconciled,
            "reconciled raw_items stuck in extracting before claim"
        );
    }

    let entity_stats = reconcile_pending_entities(&raw_repo, limit.max(1)).await?;
    if entity_stats.leaders > 0 || entity_stats.duplicates_marked > 0 {
        tracing::info!(
            leaders = entity_stats.leaders,
            duplicates_marked = entity_stats.duplicates_marked,
            "entity resolution on pending backlog"
        );
    }

    let batch = raw_repo.claim_pending_batch(limit).await?;
    let mut stats = ExtractStats::default();

    for raw in batch {
        match process_one(&raw_repo, &extracted_repo, &snapshots, &llm, &raw).await {
            Ok(outcome) => {
                stats.extracted += 1;
                if outcome == ExtractOutcome::QualityWarn {
                    stats.quality_warn += 1;
                }
            }
            Err(e) => {
                tracing::warn!(raw_item_id = %raw.id, error = %e, "extract failed");
                if e.to_string().contains("extract_quality_low") {
                    stats.quality_rejected += 1;
                }
                stats.failed += 1;
            }
        }
    }

    metrics::record_extract_pass(
        stats.extracted,
        stats.failed,
        stats.quality_warn,
        stats.quality_rejected,
        started.elapsed(),
    );
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
    let snapshots = PgToolMetricsSnapshotRepository::new(db);
    raw_repo
        .mark_status(raw_item_id, crate::domain::RawItemStatus::Pending)
        .await
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    let raw = raw_repo
        .get(raw_item_id)
        .await
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    process_one(&raw_repo, &extracted_repo, &snapshots, &llm, &raw)
        .await
        .map(|_| ())
}

/// Per-item result after a successful DB write.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ExtractOutcome {
    /// Quality score ≥ 70.
    Pass,
    /// Quality score 40–69 — persisted with `low_confidence`.
    QualityWarn,
}

async fn process_one(
    raw_repo: &PgRawItemRepository,
    extracted_repo: &PgExtractedItemRepository,
    snapshots: &PgToolMetricsSnapshotRepository,
    llm: &Arc<dyn LlmProvider>,
    raw: &crate::domain::RawItem,
) -> anyhow::Result<ExtractOutcome> {
    let mut audits = Vec::new();

    let outcome = llm_extract_with_retry(llm, raw, &mut audits).await;

    match outcome {
        Ok((fields, resp)) => {
            let quality = assess_extract_quality(&fields);

            if quality.tier == QualityTier::Reject {
                tracing::info!(
                    raw_item_id = %raw.id,
                    quality_score = quality.score,
                    missing = ?quality.missing,
                    "extract rejected by quality gate"
                );
                audits.push(audit_entry(
                    0,
                    "quality_rejected",
                    format!(
                        "score={} missing={:?} warnings={:?}",
                        quality.score, quality.missing, quality.warnings
                    ),
                    None,
                ));
                for a in &audits {
                    raw_repo.append_extract_attempt(raw.id, a.clone()).await?;
                }
                raw_repo.mark_status(raw.id, RawItemStatus::Failed).await?;
                metrics::record_extract_quality_rejected(quality.score);
                return Err(anyhow::anyhow!(
                    "extract_quality_low: score {} below threshold",
                    quality.score
                ));
            }

            let mut new_item =
                fields.into_new_extracted_item(raw.id, extractor_id(), EXTRACTOR_VERSION, &resp);
            if let Some(serde_json::Value::Object(map)) = &mut new_item.metadata_json {
                map.insert("extract_attempts".to_string(), json!(audits));
                map.insert("extract_quality".to_string(), quality.to_metadata());
                if quality.tier == QualityTier::Warn {
                    map.insert("quality_warn".to_string(), json!(true));
                    map.insert("low_confidence".to_string(), json!(true));
                }
                if let Some(adoption) = adoption_from_raw(raw) {
                    let adoption = match velocity_for_raw(snapshots, raw).await {
                        Ok(velocity) => enrich_adoption(adoption, &velocity),
                        Err(e) => {
                            tracing::warn!(
                                raw_item_id = %raw.id,
                                error = %e,
                                "velocity enrichment failed"
                            );
                            adoption
                        }
                    };
                    if let Some(days) = adoption.days_since_push {
                        map.insert("days_since_activity".to_string(), json!(days));
                    }
                    map.insert("adoption".to_string(), adoption.to_json());
                }
            }

            extracted_repo.insert(&new_item).await?;
            raw_repo
                .mark_status(raw.id, RawItemStatus::Extracted)
                .await?;

            metrics::record_extract_quality_score(quality.score);
            if quality.tier == QualityTier::Warn {
                metrics::record_extract_quality_warn();
            }

            Ok(if quality.tier == QualityTier::Warn {
                ExtractOutcome::QualityWarn
            } else {
                ExtractOutcome::Pass
            })
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
