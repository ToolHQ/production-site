//! Run collect pipelines with bounded concurrency and per-source isolation.

use std::sync::Arc;
use std::time::Instant;

use chrono::{DateTime, Utc};
use futures::stream::{self, StreamExt};
use uuid::Uuid;

use crate::collector::github::{GitHubClient, GithubCollector};
use crate::collector::rss::RssCollector;
use crate::collector::web::{WebCollector, WebFetcher, WebFetcherConfig};
use crate::collector::Collector;
use crate::config::AppConfig;
use crate::curation::{record_metrics_snapshot, resolve_entity_for_inserted, tool_key_from_new_raw_item};
use crate::db::Database;
use crate::domain::{Source, SourceType};
use crate::metrics;
use crate::repos::{
    PgRawItemRepository, PgSourceRepository, PgToolMetricsSnapshotRepository,
    RawItemRepository, SourceRepository,
};

/// Aggregated counters printed by the CLI.
#[derive(Debug, Default, Clone, Copy)]
pub struct CollectStats {
    /// Rows newly inserted (first-seen idempotency key).
    pub collected: u64,
    /// Rows skipped because `(source_id, content_hash)` already existed.
    pub skipped: u64,
    /// Rows marked `skipped` as cross-source duplicates (**T-231**).
    pub entity_duplicates: u64,
    /// Sources where fetch/parse failed before inserts.
    pub source_errors: u64,
    /// Sources matching the filter (size of the work batch).
    pub total_sources: u64,
    /// Enabled sources skipped because `poll_interval_minutes` has not elapsed
    /// since `last_polled_at` (batch collect only).
    pub skipped_poll: u64,
}

/// Execute one collect pass for every enabled source of `filter_type`, or a
/// single source when `source_id` is set.
///
/// # Errors
///
/// Returns when configuration or repository access fails (e.g. missing
/// source id). Transport failures on individual sources are counted in
/// [`CollectStats::source_errors`] instead of aborting the whole run.
pub async fn run_collect(
    db: &Database,
    config: &AppConfig,
    filter_type: SourceType,
    source_id: Option<Uuid>,
) -> anyhow::Result<CollectStats> {
    let started = Instant::now();
    let (sources, skipped_poll) = list_sources(db, filter_type, source_id).await?;
    let total_sources = sources.len() as u64;

    if sources.is_empty() {
        tracing::info!(
            skipped_poll,
            "collect: nothing to do (no matching sources or all inside poll interval)"
        );
        let stats = CollectStats {
            total_sources: 0,
            skipped_poll,
            ..CollectStats::default()
        };
        metrics::record_collect_pass(
            filter_type,
            stats.collected,
            stats.skipped,
            stats.source_errors,
            stats.skipped_poll,
            started.elapsed(),
        );
        return Ok(stats);
    }

    let collector = build_collector(filter_type, config)?;
    let concurrency = config.collect_concurrency.max(1);

    let mut stream = stream::iter(sources)
        .map(|src| {
            let db = db.clone();
            let collector = Arc::clone(&collector);
            async move {
                let raw_repo = PgRawItemRepository::new(&db);
                let source_repo = PgSourceRepository::new(&db);
                let snapshots = PgToolMetricsSnapshotRepository::new(&db);
                process_one_source(
                    collector.as_ref(),
                    &raw_repo,
                    &snapshots,
                    &source_repo,
                    &src,
                )
                .await
            }
        })
        .buffer_unordered(concurrency);

    let mut stats = CollectStats {
        total_sources,
        skipped_poll,
        ..CollectStats::default()
    };

    while let Some(chunk) = stream.next().await {
        match chunk {
            OneSource::Ok {
                collected,
                skipped,
                entity_duplicates,
            } => {
                stats.collected += collected;
                stats.skipped += skipped;
                stats.entity_duplicates += entity_duplicates;
            }
            OneSource::Failed => {
                stats.source_errors += 1;
            }
        }
    }

    metrics::record_collect_pass(
        filter_type,
        stats.collected,
        stats.skipped,
        stats.source_errors,
        stats.skipped_poll,
        started.elapsed(),
    );

    Ok(stats)
}

fn build_collector(
    filter_type: SourceType,
    config: &AppConfig,
) -> anyhow::Result<Arc<dyn Collector>> {
    match filter_type {
        SourceType::Rss => {
            let client = RssCollector::default_http_client()?;
            Ok(Arc::new(RssCollector::new(
                client,
                config.max_items_per_run,
            )))
        }
        SourceType::GithubReleases | SourceType::GithubRepo => {
            let client = RssCollector::default_http_client()?;
            let gh = GitHubClient::new(client, config.github_token.clone());
            Ok(Arc::new(GithubCollector::new(
                gh,
                config.max_items_per_run,
            )))
        }
        SourceType::Webpage => {
            let client = WebFetcher::default_http_client()?;
            let fetcher = WebFetcher::new(client, WebFetcherConfig::default());
            Ok(Arc::new(WebCollector::new(fetcher)))
        }
        other => anyhow::bail!("collect not implemented for source_type {other:?}"),
    }
}

enum OneSource {
    Ok {
        collected: u64,
        skipped: u64,
        entity_duplicates: u64,
    },
    Failed,
}

async fn process_one_source(
    collector: &dyn Collector,
    raw_repo: &PgRawItemRepository,
    snapshots: &PgToolMetricsSnapshotRepository,
    source_repo: &PgSourceRepository,
    source: &Source,
) -> OneSource {
    match collector.collect(source).await {
        Ok(items) => {
            let mut collected = 0u64;
            let mut skipped = 0u64;
            let mut entity_duplicates = 0u64;
            for item in items {
                match raw_repo.insert_idempotent(&item).await {
                    Ok(Some(row)) => {
                        collected += 1;
                        match resolve_entity_for_inserted(raw_repo, row.id, &item).await {
                            Ok(entity) => {
                                if entity.duplicates_marked > 0 {
                                    entity_duplicates += entity.duplicates_marked;
                                    collected = collected.saturating_sub(entity.duplicates_marked);
                                }
                            }
                            Err(e) => tracing::warn!(
                                raw_item_id = %row.id,
                                error = %e,
                                "entity resolution failed after insert"
                            ),
                        }
                        if let Some(identity) = tool_key_from_new_raw_item(&item) {
                            if let Err(e) = record_metrics_snapshot(
                                snapshots,
                                &identity.tool_key,
                                source.id,
                                item.metadata_json.as_ref(),
                            )
                            .await
                            {
                                tracing::warn!(
                                    raw_item_id = %row.id,
                                    tool_key = %identity.tool_key,
                                    error = %e,
                                    "tool_metrics_snapshot insert failed"
                                );
                            }
                        }
                        tracing::trace!(
                            source_id = %source.id,
                            raw_item_id = %row.id,
                            external_id = ?item.external_id,
                            "raw_item inserted"
                        );
                    }
                    Ok(None) => {
                        skipped += 1;
                    }
                    Err(e) => {
                        tracing::error!(
                            source_id = %source.id,
                            external_id = ?item.external_id,
                            error = %e,
                            "raw_items insert failed"
                        );
                    }
                }
            }
            if let Err(e) = source_repo.touch_polled(source.id, None).await {
                tracing::error!(
                    source_id = %source.id,
                    error = %e,
                    "touch_polled failed after successful collect"
                );
            }
            OneSource::Ok {
                collected,
                skipped,
                entity_duplicates,
            }
        }
        Err(e) => {
            tracing::warn!(
                source_id = %source.id,
                error = %e,
                "collector failed for source"
            );
            let msg = format!("{e}");
            if let Err(te) = source_repo.touch_polled(source.id, Some(&msg)).await {
                tracing::error!(
                    source_id = %source.id,
                    error = %te,
                    "touch_polled failed after collector error"
                );
            }
            OneSource::Failed
        }
    }
}

async fn list_sources(
    db: &Database,
    filter_type: SourceType,
    source_id: Option<Uuid>,
) -> anyhow::Result<(Vec<Source>, u64)> {
    let repo = PgSourceRepository::new(db);
    if let Some(id) = source_id {
        let s = repo.get(id).await?;
        if !s.enabled {
            anyhow::bail!("source {id} is disabled");
        }
        if s.source_type != filter_type {
            anyhow::bail!(
                "source {id} is {:?}, expected {:?}",
                s.source_type,
                filter_type
            );
        }
        return Ok((vec![s], 0));
    }

    let now = Utc::now();
    let all = repo.list_enabled().await?;
    let mut skipped_poll = 0u64;
    let filtered: Vec<Source> = all
        .into_iter()
        .filter(|s| s.source_type == filter_type)
        .filter(|s| {
            if source_poll_due(s, now) {
                true
            } else {
                skipped_poll += 1;
                false
            }
        })
        .collect();
    Ok((filtered, skipped_poll))
}

/// Whether a batch collect should hit this source now (`last_polled_at` + interval).
#[inline]
fn source_poll_due(source: &Source, now: DateTime<Utc>) -> bool {
    match source.last_polled_at {
        None => true,
        Some(last) => {
            let mins = source.poll_interval_minutes.max(1);
            let interval = chrono::Duration::minutes(i64::from(mins));
            now >= last + interval
        }
    }
}

#[cfg(test)]
mod poll_due_tests {
    use super::*;
    use crate::domain::{Source, SourceType};
    use chrono::Duration as ChDuration;
    use uuid::Uuid;

    fn sample_source(last_polled_at: Option<DateTime<Utc>>, poll_interval_minutes: i32) -> Source {
        Source {
            id: Uuid::nil(),
            name: "t".into(),
            source_type: SourceType::Rss,
            url: "https://example.com/feed.xml".into(),
            enabled: true,
            poll_interval_minutes,
            last_polled_at,
            last_error: None,
            metadata_json: serde_json::json!({}),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        }
    }

    #[test]
    fn never_polled_is_always_due() {
        let now = Utc::now();
        assert!(source_poll_due(&sample_source(None, 30), now));
    }

    #[test]
    fn inside_poll_window_is_skipped() {
        let now = Utc::now();
        let last = now - ChDuration::minutes(5);
        assert!(!source_poll_due(&sample_source(Some(last), 30), now));
    }

    #[test]
    fn after_poll_window_is_due() {
        let now = Utc::now();
        let last = now - ChDuration::minutes(45);
        assert!(source_poll_due(&sample_source(Some(last), 30), now));
    }
}
