//! Manual reprocess for a single extracted item (**T-173**).

use std::sync::Arc;

use uuid::Uuid;

use crate::config::AppConfig;
use crate::db::Database;
use crate::llm::LlmProvider;
use crate::pipeline::extract::extract_single_raw_item;
use crate::pipeline::score::score_single_extracted_item;
use crate::repos::{
    ExtractedItemRepository, PgExtractedItemRepository,
};

/// Which pipeline stages to rerun.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReprocessStage {
    /// LLM extract only (new `extracted_items.version`).
    Extract,
    /// Deterministic score on the latest extracted row for this raw item.
    Score,
    /// Extract then score the new version.
    All,
}

impl ReprocessStage {
    /// Parse API/CLI string (`extract`, `score`, `all`).
    pub fn parse(s: &str) -> anyhow::Result<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "extract" => Ok(Self::Extract),
            "score" => Ok(Self::Score),
            "all" => Ok(Self::All),
            other => anyhow::bail!("unknown reprocess stage {other:?}; use extract|score|all"),
        }
    }
}

/// Outcome of [`run_reprocess`].
#[derive(Debug, Clone)]
pub struct ReprocessResult {
    /// Anchor extracted item id from the request.
    pub extracted_item_id: Uuid,
    /// Parent raw item.
    pub raw_item_id: Uuid,
    /// Newest extracted row after extract (if run).
    pub latest_extracted_item_id: Option<Uuid>,
    /// Version number of the newest extracted row (if run).
    pub latest_version: Option<i32>,
    /// Whether a score row was written.
    pub scored: bool,
}

/// Re-run extract and/or score for the raw item behind `extracted_item_id`.
///
/// Extract resets the raw row to `pending`, runs a single-item extract (new version).
/// Score uses the **latest** extracted version for that raw item.
///
/// # Errors
///
/// When the item is missing, LLM is disabled for extract stages, or the pipeline fails.
pub async fn run_reprocess(
    db: &Database,
    config: &AppConfig,
    llm: Arc<dyn LlmProvider>,
    extracted_item_id: Uuid,
    stage: ReprocessStage,
) -> anyhow::Result<ReprocessResult> {
    let extracted_repo = PgExtractedItemRepository::new(db);

    let anchor = extracted_repo.get(extracted_item_id).await?;
    let raw_item_id = anchor.raw_item_id;

    let mut result = ReprocessResult {
        extracted_item_id,
        raw_item_id,
        latest_extracted_item_id: None,
        latest_version: None,
        scored: false,
    };

    let run_extract = matches!(stage, ReprocessStage::Extract | ReprocessStage::All);
    let run_score = matches!(stage, ReprocessStage::Score | ReprocessStage::All);

    if run_extract {
        extract_single_raw_item(db, config, llm.clone(), raw_item_id).await?;
        let latest = extracted_repo.get_latest_for_raw_item(raw_item_id).await?;
        result.latest_extracted_item_id = Some(latest.id);
        result.latest_version = Some(latest.version);
    }

    if run_score {
        let target_id = if let Some(id) = result.latest_extracted_item_id {
            id
        } else {
            extracted_repo
                .get_latest_for_raw_item(raw_item_id)
                .await?
                .id
        };
        score_single_extracted_item(db, config, llm.clone(), target_id).await?;
        result.scored = true;
        if result.latest_extracted_item_id.is_none() {
            let latest = extracted_repo.get(target_id).await?;
            result.latest_extracted_item_id = Some(latest.id);
            result.latest_version = Some(latest.version);
        }
    }

    Ok(result)
}
