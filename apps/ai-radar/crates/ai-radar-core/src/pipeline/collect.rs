//! Run the RSS collect pipeline with bounded concurrency and per-source isolation.

use futures::stream::{self, StreamExt};
use uuid::Uuid;

use crate::collector::rss::RssCollector;
use crate::collector::Collector;
use crate::config::AppConfig;
use crate::db::Database;
use crate::domain::{Source, SourceType};
use crate::repos::{PgRawItemRepository, PgSourceRepository, RawItemRepository, SourceRepository};

/// Aggregated counters printed by the CLI.
#[derive(Debug, Default, Clone, Copy)]
pub struct CollectStats {
    /// Rows newly inserted (first-seen idempotency key).
    pub collected: u64,
    /// Rows skipped because `(source_id, content_hash)` already existed.
    pub skipped: u64,
    /// Sources where fetch/parse failed before inserts.
    pub source_errors: u64,
    /// Sources matching the filter (size of the work batch).
    pub total_sources: u64,
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
    let sources = list_sources(db, filter_type, source_id).await?;
    let total_sources = sources.len() as u64;

    if sources.is_empty() {
        tracing::info!("collect: no matching sources — nothing to do");
        return Ok(CollectStats {
            total_sources: 0,
            ..CollectStats::default()
        });
    }

    let client = RssCollector::default_http_client()?;
    let collector = RssCollector::new(client, config.max_items_per_run);
    let concurrency = config.collect_concurrency.max(1);

    let mut stream = stream::iter(sources)
        .map(|src| {
            let db = db.clone();
            let collector = collector.clone();
            async move {
                let raw_repo = PgRawItemRepository::new(&db);
                let source_repo = PgSourceRepository::new(&db);
                process_one_source(&collector, &raw_repo, &source_repo, &src).await
            }
        })
        .buffer_unordered(concurrency);

    let mut stats = CollectStats {
        total_sources,
        ..CollectStats::default()
    };

    while let Some(chunk) = stream.next().await {
        match chunk {
            OneSource::Ok { collected, skipped } => {
                stats.collected += collected;
                stats.skipped += skipped;
            }
            OneSource::Failed => {
                stats.source_errors += 1;
            }
        }
    }

    Ok(stats)
}

enum OneSource {
    Ok { collected: u64, skipped: u64 },
    Failed,
}

async fn process_one_source(
    collector: &RssCollector,
    raw_repo: &PgRawItemRepository,
    source_repo: &PgSourceRepository,
    source: &Source,
) -> OneSource {
    match collector.collect(source).await {
        Ok(items) => {
            let mut collected = 0u64;
            let mut skipped = 0u64;
            for item in items {
                match raw_repo.insert_idempotent(&item).await {
                    Ok(Some(_)) => collected += 1,
                    Ok(None) => skipped += 1,
                    Err(e) => {
                        tracing::error!(source_id = %source.id, error = %e, "raw_items insert");
                    }
                }
            }
            if let Err(e) = source_repo.touch_polled(source.id, None).await {
                tracing::error!(source_id = %source.id, error = %e, "touch_polled success path");
            }
            OneSource::Ok { collected, skipped }
        }
        Err(e) => {
            tracing::warn!(source_id = %source.id, error = %e, "collector failed");
            let msg = format!("{e}");
            if let Err(te) = source_repo.touch_polled(source.id, Some(&msg)).await {
                tracing::error!(source_id = %source.id, error = %te, "touch_polled error path");
            }
            OneSource::Failed
        }
    }
}

async fn list_sources(
    db: &Database,
    filter_type: SourceType,
    source_id: Option<Uuid>,
) -> anyhow::Result<Vec<Source>> {
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
        return Ok(vec![s]);
    }

    let all = repo.list_enabled().await?;
    Ok(all
        .into_iter()
        .filter(|s| s.source_type == filter_type)
        .collect())
}
