//! Scoring pass over `extracted_items` (**T-166** + optional LLM **T-167**).

use std::sync::Arc;
use std::time::Instant;

use crate::config::AppConfig;
use crate::curation::adoption::adoption_from_extracted;
use crate::db::Database;
use crate::llm::build_llm_provider;
use crate::llm::LlmProvider;
use crate::metrics;
use crate::repos::{
    ExtractedItemRepository, PgExtractedItemRepository, PgScoreRepository, ScoreRepository,
};
use crate::scorer::{
    log_llm_cost, merged_to_new_score, LlmScorer, MergePolicy, MergedScoreResult, Scorer,
    SCORING_VERSION_DETERMINISTIC_V1, SCORING_VERSION_MERGED_V1,
};

/// Default hours before a row is eligible for rescoring (unless `--rescore-all`).
pub const DEFAULT_SCORE_STALE_HOURS: i64 = 24;

/// Counters for CLI / API.
#[derive(Debug, Default, Clone, Copy)]
pub struct ScoreStats {
    /// Rows scored successfully.
    pub scored: u64,
    /// Rows that failed validation or DB insert.
    pub failed: u64,
}

fn scoring_version_for_config(config: &AppConfig) -> &'static str {
    if config.llm_scoring_enabled {
        SCORING_VERSION_MERGED_V1
    } else {
        SCORING_VERSION_DETERMINISTIC_V1
    }
}

/// Score up to `limit` extracted items (deterministic, optionally merged with LLM).
///
/// # Errors
///
/// Propagates database errors. Returns an error when `LLM_SCORING_ENABLED=true` but
/// `LLM_ENABLED=false`.
pub async fn run_score(
    db: &Database,
    config: &AppConfig,
    limit: i64,
    stale_hours: i64,
    rescore_all: bool,
) -> anyhow::Result<ScoreStats> {
    let llm = build_llm_provider(config);
    run_score_with_llm(db, config, llm, limit, stale_hours, rescore_all).await
}

/// Score with an explicit LLM provider (tests).
///
/// # Errors
///
/// Same as [`run_score`].
pub async fn run_score_with_llm(
    db: &Database,
    config: &AppConfig,
    llm: Arc<dyn LlmProvider>,
    limit: i64,
    stale_hours: i64,
    rescore_all: bool,
) -> anyhow::Result<ScoreStats> {
    if config.llm_scoring_enabled && !config.llm_enabled {
        anyhow::bail!(
            "LLM_SCORING_ENABLED=true requires LLM_ENABLED=true (configure LLM_API_KEY and LLM_MODEL)"
        );
    }

    let started = Instant::now();
    let extracted = PgExtractedItemRepository::new(db);
    let scores = PgScoreRepository::new(db);
    let deterministic = Scorer::v1();
    let llm_scorer = LlmScorer;
    let policy = MergePolicy::from_config(
        config.llm_scoring_enabled,
        config.llm_scoring_deterministic_weight,
        config.llm_scoring_llm_weight,
    );
    let scoring_version = scoring_version_for_config(config);

    let batch = extracted
        .list_pending_scoring(limit, scoring_version, stale_hours, rescore_all)
        .await?;

    let mut stats = ScoreStats::default();

    for row in batch {
        let det = deterministic.score(&row);
        let llm_opinion = if matches!(policy, MergePolicy::Weighted { .. }) {
            match llm_scorer.evaluate(llm.as_ref(), &row).await {
                Ok((opinion, resp)) => {
                    log_llm_cost(&resp.model, &resp);
                    Some(opinion)
                }
                Err(e) => {
                    tracing::warn!(
                        extracted_item_id = %row.id,
                        error = %e,
                        "llm scorer failed; using deterministic only"
                    );
                    None
                }
            }
        } else {
            None
        };

        let merged = MergedScoreResult::merge(det, llm_opinion, policy);
        let model = config.llm_model.as_deref();
        let new_score = merged_to_new_score(&merged, row.id, model, None);

        match scores.insert(&new_score).await {
            Ok(_) => {
                tracing::info!(
                    extracted_item_id = %row.id,
                    points = merged.final_points,
                    decision = %merged.decision.as_str(),
                    scoring_version = %new_score.scoring_version,
                    "score persisted"
                );
                if let Some(adoption) = adoption_from_extracted(&row.metadata_json) {
                    metrics::record_adoption_tier(
                        merged.decision.as_str(),
                        adoption.stars_tier.as_str(),
                    );
                }
                stats.scored += 1;
            }
            Err(e) => {
                tracing::warn!(
                    extracted_item_id = %row.id,
                    error = %e,
                    "score insert failed"
                );
                stats.failed += 1;
            }
        }
    }

    metrics::record_score_pass(stats.scored, stats.failed, started.elapsed());
    Ok(stats)
}

/// Score one extracted row by id (reprocess / ops).
///
/// # Errors
///
/// Propagates repository or validation errors.
pub async fn score_single_extracted_item(
    db: &Database,
    config: &AppConfig,
    llm: Arc<dyn LlmProvider>,
    extracted_item_id: uuid::Uuid,
) -> anyhow::Result<()> {
    if config.llm_scoring_enabled && !config.llm_enabled {
        anyhow::bail!("LLM_SCORING_ENABLED=true requires LLM_ENABLED=true");
    }
    let extracted = PgExtractedItemRepository::new(db);
    let scores = PgScoreRepository::new(db);
    let row = extracted.get(extracted_item_id).await?;
    let det = Scorer::v1().score(&row);
    let policy = MergePolicy::from_config(
        config.llm_scoring_enabled,
        config.llm_scoring_deterministic_weight,
        config.llm_scoring_llm_weight,
    );
    let llm_opinion = if matches!(policy, MergePolicy::Weighted { .. }) {
        LlmScorer
            .evaluate(llm.as_ref(), &row)
            .await
            .ok()
            .map(|(o, _)| o)
    } else {
        None
    };
    let merged = MergedScoreResult::merge(det, llm_opinion, policy);
    let new_score = merged_to_new_score(
        &merged,
        row.id,
        config.llm_model.as_deref(),
        None,
    );
    scores.insert(&new_score).await?;
    if let Some(adoption) = adoption_from_extracted(&row.metadata_json) {
        metrics::record_adoption_tier(merged.decision.as_str(), adoption.stars_tier.as_str());
    }
    Ok(())
}
