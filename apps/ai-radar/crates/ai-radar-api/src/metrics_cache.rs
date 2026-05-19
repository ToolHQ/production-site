//! Cached DB-backed gauge values for `GET /metrics` (**T-263**).
//!
//! Prometheus scrapes every ~15–30s; embedding coverage queries are expensive
//! and fail loudly on transient DNS/pool blips during rollouts. Cache +
//! stale-while-revalidate keeps gauges stable and logs quiet.

use std::time::{Duration, Instant};

use tokio::sync::RwLock;

/// Default refresh interval for DB-backed gauges.
pub const METRICS_GAUGE_TTL: Duration = Duration::from_secs(60);

/// Snapshot of gauges derived from Postgres.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DbGaugeSnapshot {
    pub pending_raw_items: i64,
    pub embeddings_pending: Option<i64>,
    pub embeddings_coverage_pct: Option<f32>,
    pub refreshed_at: Instant,
}

struct CachedEntry {
    snapshot: DbGaugeSnapshot,
}

/// In-memory cache with TTL and stale fallback.
#[derive(Default)]
pub struct MetricsGaugeCache {
    inner: RwLock<Option<CachedEntry>>,
    ttl: Duration,
}

impl MetricsGaugeCache {
    /// Build a cache with the given TTL.
    #[must_use]
    pub fn new(ttl: Duration) -> Self {
        Self {
            inner: RwLock::new(None),
            ttl,
        }
    }

    /// Return a fresh snapshot if younger than TTL.
    pub async fn fresh(&self) -> Option<DbGaugeSnapshot> {
        let guard = self.inner.read().await;
        guard.as_ref().and_then(|entry| {
            if entry.snapshot.refreshed_at.elapsed() < self.ttl {
                Some(entry.snapshot)
            } else {
                None
            }
        })
    }

    /// Return the last snapshot regardless of age (stale-while-revalidate).
    pub async fn stale(&self) -> Option<DbGaugeSnapshot> {
        self.inner.read().await.as_ref().map(|e| e.snapshot)
    }

    /// Store a new snapshot (typically after a successful DB refresh).
    pub async fn store(&self, snapshot: DbGaugeSnapshot) {
        *self.inner.write().await = Some(CachedEntry { snapshot });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn fresh_expires_after_ttl() {
        let cache = MetricsGaugeCache::new(Duration::from_millis(20));
        let snap = DbGaugeSnapshot {
            pending_raw_items: 3,
            embeddings_pending: Some(10),
            embeddings_coverage_pct: Some(91.0),
            refreshed_at: Instant::now(),
        };
        cache.store(snap).await;
        assert_eq!(cache.fresh().await, Some(snap));
        tokio::time::sleep(Duration::from_millis(25)).await;
        assert!(cache.fresh().await.is_none());
        assert_eq!(cache.stale().await, Some(snap));
    }
}
