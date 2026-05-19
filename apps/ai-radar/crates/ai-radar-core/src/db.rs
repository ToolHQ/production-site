//! Postgres connection pool and shared repository error type.
//!
//! Centralizes pool construction so every binary (`ai-radar-api`,
//! `ai-radar-cli`, integration tests) gets the same defaults — bounded
//! connection count, short acquire timeout, and the rustls-only TLS
//! stack pinned by the workspace `sqlx` feature flags.

use std::time::Duration;

use sqlx::postgres::PgPoolOptions;
use sqlx::{Error as SqlxError, PgPool};

/// Default `max_connections` for the API and CLI pools.
///
/// Keeps usage of the cluster-shared Postgres bounded; tunable per binary
/// when needed. See `docs/AI-RADAR-DECISIONS.md` for the rationale.
pub const DEFAULT_MAX_CONNECTIONS: u32 = 8;
/// Default `min_connections`.
pub const DEFAULT_MIN_CONNECTIONS: u32 = 1;
/// Default acquire timeout.
pub const DEFAULT_ACQUIRE_TIMEOUT: Duration = Duration::from_secs(5);
/// Default per-statement test interval (ping-style health probe).
pub const DEFAULT_TEST_BEFORE_ACQUIRE_INTERVAL: Duration = Duration::from_secs(60);

/// Pool construction options. Defaults match the values applied by
/// [`Database::connect`] when `Default` is used.
#[derive(Debug, Clone)]
pub struct PoolConfig {
    /// Maximum number of pooled connections.
    pub max_connections: u32,
    /// Minimum kept-alive connections.
    pub min_connections: u32,
    /// How long a caller waits to acquire a connection before erroring.
    pub acquire_timeout: Duration,
}

impl Default for PoolConfig {
    fn default() -> Self {
        Self {
            max_connections: DEFAULT_MAX_CONNECTIONS,
            min_connections: DEFAULT_MIN_CONNECTIONS,
            acquire_timeout: DEFAULT_ACQUIRE_TIMEOUT,
        }
    }
}

/// Errors surfaced by the database layer to the rest of the codebase.
///
/// Repositories should map every `sqlx::Error` to one of these variants so
/// callers can pattern-match without depending on `sqlx` directly.
#[derive(Debug, thiserror::Error)]
pub enum RepoError {
    /// Row was not found by the requested key.
    #[error("not found")]
    NotFound,

    /// Unique constraint violation (e.g. duplicate `(source_id, content_hash)`).
    #[error("conflict: {0}")]
    Conflict(String),

    /// Validation error before the SQL even runs (e.g. invalid enum value).
    #[error("validation: {0}")]
    Validation(String),

    /// Catch-all for any other [`sqlx::Error`]. Boxed because the inner
    /// error is large enough to trigger `clippy::result_large_err`.
    #[error("database error: {0}")]
    Database(#[from] Box<SqlxError>),
}

impl RepoError {
    /// Convenience wrapper that boxes a [`sqlx::Error`] into
    /// [`RepoError::Database`]. Repositories use this from `?` chains.
    #[must_use]
    pub fn from_sqlx(error: SqlxError) -> Self {
        if let SqlxError::Database(ref db_err) = error {
            // 23505 = unique_violation in Postgres.
            if db_err.code().as_deref() == Some("23505") {
                return RepoError::Conflict(db_err.message().to_string());
            }
        }
        if matches!(error, SqlxError::RowNotFound) {
            return RepoError::NotFound;
        }
        RepoError::Database(Box::new(error))
    }

    /// True for pool acquire timeout, DNS blips, and other short-lived faults (**T-265**).
    #[must_use]
    pub fn is_transient(&self) -> bool {
        match self {
            RepoError::Database(err) => {
                let msg = err.to_string().to_ascii_lowercase();
                msg.contains("pool timed out")
                    || msg.contains("connection refused")
                    || msg.contains("connection reset")
                    || msg.contains("name or service not known")
                    || msg.contains("communicating with database")
                    || msg.contains("timeout")
            }
            _ => false,
        }
    }
}

/// Convenience alias used by repositories.
pub type RepoResult<T> = Result<T, RepoError>;

/// Thin wrapper around the `SQLx` pool plus a slot for migration metadata
/// when the caller wants to surface it from `/health` etc.
#[derive(Debug, Clone)]
pub struct Database {
    /// The underlying `SQLx` pool. Cheap to clone (it is `Arc`-internal).
    pub pool: PgPool,
}

impl Database {
    /// Open a Postgres pool against `database_url` using
    /// [`PoolConfig::default`].
    ///
    /// # Errors
    ///
    /// Returns `RepoError::Database` if the pool cannot be opened (DNS,
    /// authentication, TLS, or initial probe failure).
    pub async fn connect(database_url: &str) -> RepoResult<Self> {
        Self::connect_with(database_url, PoolConfig::default()).await
    }

    /// Open a Postgres pool with explicit options.
    ///
    /// # Errors
    ///
    /// Same as [`Database::connect`].
    pub async fn connect_with(database_url: &str, config: PoolConfig) -> RepoResult<Self> {
        let pool = PgPoolOptions::new()
            .max_connections(config.max_connections)
            .min_connections(config.min_connections)
            .acquire_timeout(config.acquire_timeout)
            .test_before_acquire(false)
            .connect(database_url)
            .await
            .map_err(RepoError::from_sqlx)?;
        Ok(Self { pool })
    }

    /// Run pending `SQLx` migrations from the embedded `migrations/` folder.
    ///
    /// # Errors
    ///
    /// Returns `RepoError::Database` if any migration fails. Safe to call
    /// at startup of long-running binaries.
    pub async fn migrate(&self) -> RepoResult<()> {
        sqlx::migrate!("../../migrations")
            .run(&self.pool)
            .await
            .map_err(|e| RepoError::Database(Box::new(SqlxError::Migrate(Box::new(e)))))?;
        Ok(())
    }

    /// Cheap connectivity check for Kubernetes readiness (**T-264**).
    ///
    /// # Errors
    ///
    /// Returns [`RepoError::Database`] when Postgres is unreachable or the query fails.
    pub async fn ping(&self) -> RepoResult<()> {
        sqlx::query_scalar::<_, i32>("SELECT 1")
            .fetch_one(&self.pool)
            .await
            .map(|_| ())
            .map_err(RepoError::from_sqlx)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pool_config_defaults_match_constants() {
        let cfg = PoolConfig::default();
        assert_eq!(cfg.max_connections, DEFAULT_MAX_CONNECTIONS);
        assert_eq!(cfg.min_connections, DEFAULT_MIN_CONNECTIONS);
        assert_eq!(cfg.acquire_timeout, DEFAULT_ACQUIRE_TIMEOUT);
    }

    #[test]
    fn from_sqlx_maps_row_not_found() {
        let mapped = RepoError::from_sqlx(SqlxError::RowNotFound);
        matches!(mapped, RepoError::NotFound);
    }

    #[test]
    fn is_transient_for_pool_timeout() {
        let err = RepoError::Database(Box::new(SqlxError::PoolTimedOut));
        assert!(err.is_transient());
    }
}
