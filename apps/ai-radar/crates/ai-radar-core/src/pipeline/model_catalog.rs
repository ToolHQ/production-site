//! OpenRouter model catalog sync and diff (**T-270**).

use std::collections::{BTreeMap, HashMap};
use std::time::Instant;

use reqwest::header::USER_AGENT;
use serde::Deserialize;
use tracing::info;
use uuid::Uuid;

use crate::config::AppConfig;
use crate::db::{Database, RepoResult};
use crate::domain::model_catalog::{
    ModelCatalogDiff, ModelCatalogEntry, ModelCatalogEventType, PROVIDER_OPENROUTER,
};
use crate::metrics;
use crate::repos::model_catalog::PgModelCatalogRepository;
use crate::repos::ModelCatalogRepository;

/// Outcome of one catalog sync pass.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelCatalogSyncStats {
    pub run_id: Uuid,
    pub model_count: usize,
    pub events_count: usize,
    pub added: usize,
    pub removed: usize,
    pub price_changes: usize,
}

/// Compare fetched catalog against prior state.
#[must_use]
pub fn diff_catalog(
    previous: &HashMap<String, ModelCatalogEntry>,
    current: &BTreeMap<String, ModelCatalogEntry>,
) -> Vec<ModelCatalogDiff> {
    let mut events = Vec::new();

    for (id, row) in current {
        match previous.get(id) {
            None => events.push(ModelCatalogDiff {
                model_id: id.clone(),
                event_type: ModelCatalogEventType::ModelAdded,
                prompt_price: row.prompt_price.clone(),
                completion_price: row.completion_price.clone(),
                previous_prompt_price: None,
                previous_completion_price: None,
            }),
            Some(prev) => {
                if prev.prompt_price != row.prompt_price
                    || prev.completion_price != row.completion_price
                {
                    events.push(ModelCatalogDiff {
                        model_id: id.clone(),
                        event_type: ModelCatalogEventType::PriceChange,
                        prompt_price: row.prompt_price.clone(),
                        completion_price: row.completion_price.clone(),
                        previous_prompt_price: prev.prompt_price.clone(),
                        previous_completion_price: prev.completion_price.clone(),
                    });
                }
            }
        }
    }

    for (id, prev) in previous {
        if !current.contains_key(id) {
            events.push(ModelCatalogDiff {
                model_id: id.clone(),
                event_type: ModelCatalogEventType::ModelRemoved,
                prompt_price: None,
                completion_price: None,
                previous_prompt_price: prev.prompt_price.clone(),
                previous_completion_price: prev.completion_price.clone(),
            });
        }
    }

    events.sort_by(|a, b| a.model_id.cmp(&b.model_id));
    events
}

#[derive(Debug, Deserialize)]
struct ModelsResponse {
    data: Vec<OpenRouterModel>,
}

#[derive(Debug, Deserialize)]
struct OpenRouterModel {
    id: String,
    name: Option<String>,
    pricing: Option<OpenRouterPricing>,
}

#[derive(Debug, Deserialize)]
struct OpenRouterPricing {
    prompt: Option<String>,
    completion: Option<String>,
}

/// Fetch OpenRouter `/models` (public; API key optional).
///
/// # Errors
///
/// Returns an error when HTTP fails or JSON is invalid.
pub async fn fetch_openrouter_models(models_url: &str) -> Result<Vec<ModelCatalogEntry>, String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(60))
        .build()
        .map_err(|e| format!("reqwest client: {e}"))?;

    let resp = client
        .get(models_url)
        .header(USER_AGENT, "ai-radar-model-catalog/1.0")
        .header("HTTP-Referer", "https://ai-radar.dnor.io")
        .send()
        .await
        .map_err(|e| format!("models fetch: {e}"))?;

    if !resp.status().is_success() {
        return Err(format!("models fetch HTTP {}", resp.status()));
    }

    let body: ModelsResponse = resp
        .json()
        .await
        .map_err(|e| format!("models JSON: {e}"))?;

    Ok(body
        .data
        .into_iter()
        .map(|m| ModelCatalogEntry {
            model_id: m.id,
            model_name: m.name,
            prompt_price: m.pricing.as_ref().and_then(|p| p.prompt.clone()),
            completion_price: m.pricing.as_ref().and_then(|p| p.completion.clone()),
        })
        .collect())
}

fn models_url_from_config(cfg: &AppConfig) -> String {
    let base = cfg.llm_base_url.trim_end_matches('/');
    format!("{base}/models")
}

/// Fetch, diff, persist catalog state and events.
///
/// # Errors
///
/// Propagates fetch or repository errors.
pub async fn run_model_catalog_sync(db: &Database, cfg: &AppConfig) -> RepoResult<ModelCatalogSyncStats> {
    let started = Instant::now();
    let models_url = models_url_from_config(cfg);
    let fetched = fetch_openrouter_models(&models_url)
        .await
        .map_err(|e| crate::db::RepoError::Validation(e))?;

    let current: BTreeMap<String, ModelCatalogEntry> = fetched
        .into_iter()
        .map(|e| (e.model_id.clone(), e))
        .collect();

    let repo = PgModelCatalogRepository::new(db);
    let previous = repo.load_state(PROVIDER_OPENROUTER).await?;
    let diffs = diff_catalog(&previous, &current);

    let added = diffs
        .iter()
        .filter(|d| d.event_type == ModelCatalogEventType::ModelAdded)
        .count();
    let removed = diffs
        .iter()
        .filter(|d| d.event_type == ModelCatalogEventType::ModelRemoved)
        .count();
    let price_changes = diffs
        .iter()
        .filter(|d| d.event_type == ModelCatalogEventType::PriceChange)
        .count();

    let run_id = repo
        .persist_sync(PROVIDER_OPENROUTER, &current, &diffs)
        .await?;

    let stats = ModelCatalogSyncStats {
        run_id,
        model_count: current.len(),
        events_count: diffs.len(),
        added,
        removed,
        price_changes,
    };

    metrics::record_model_catalog_sync(
        stats.events_count as u64,
        stats.added as u64,
        stats.removed as u64,
        stats.price_changes as u64,
        started.elapsed(),
    );

    info!(
        event = "model_catalog.sync",
        run_id = %run_id,
        model_count = stats.model_count,
        events_count = stats.events_count,
        added = stats.added,
        removed = stats.removed,
        price_changes = stats.price_changes,
        duration_secs = started.elapsed().as_secs_f64(),
        "model catalog sync finished"
    );

    Ok(stats)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(id: &str, prompt: &str, completion: &str) -> ModelCatalogEntry {
        ModelCatalogEntry {
            model_id: id.into(),
            model_name: None,
            prompt_price: Some(prompt.into()),
            completion_price: Some(completion.into()),
        }
    }

    #[test]
    fn diff_detects_added_removed_and_price_change() {
        let mut previous = HashMap::new();
        previous.insert("a".into(), entry("a", "0.1", "0.2"));
        previous.insert("b".into(), entry("b", "0.3", "0.4"));

        let mut current = BTreeMap::new();
        current.insert("a".into(), entry("a", "0.15", "0.2"));
        current.insert("c".into(), entry("c", "0.5", "0.6"));

        let diffs = diff_catalog(&previous, &current);
        assert_eq!(diffs.len(), 3);
        assert!(diffs.iter().any(|d| {
            d.model_id == "c" && d.event_type == ModelCatalogEventType::ModelAdded
        }));
        assert!(diffs.iter().any(|d| {
            d.model_id == "b" && d.event_type == ModelCatalogEventType::ModelRemoved
        }));
        assert!(diffs.iter().any(|d| {
            d.model_id == "a" && d.event_type == ModelCatalogEventType::PriceChange
        }));
    }
}
