//! Tracing initialization producing structured JSON logs.
//!
//! Honors `RUST_LOG` first, falling back to the level passed via
//! [`AppConfig::log_level`](crate::config::AppConfig). Idempotent: callers
//! may invoke [`init_tracing`] more than once safely (subsequent calls become
//! a no-op once a global subscriber is installed).

use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use tracing_subscriber::{fmt, EnvFilter};

/// Errors produced while installing the tracing subscriber.
#[derive(Debug, thiserror::Error)]
pub enum TelemetryError {
    /// Failed to construct the env filter (typically an invalid level).
    #[error("invalid log level filter '{level}': {source}")]
    Filter {
        /// Offending level string.
        level: String,
        /// Underlying parse error.
        #[source]
        source: tracing_subscriber::filter::ParseError,
    },
    /// A global default subscriber was already installed.
    #[error("global tracing subscriber already initialized")]
    AlreadyInitialized,
}

/// Install a JSON-formatted tracing subscriber.
///
/// Resolution order for the level filter:
///
/// 1. `RUST_LOG` (when present and parseable).
/// 2. `level` argument (e.g. `info`, `debug`, `ai_radar=trace,info`).
///
/// # Errors
///
/// Returns [`TelemetryError::Filter`] if `level` cannot be parsed, and
/// [`TelemetryError::AlreadyInitialized`] if another subscriber is already
/// installed for this process.
pub fn init_tracing(level: &str) -> Result<(), TelemetryError> {
    let filter = match EnvFilter::try_from_default_env() {
        Ok(filter) => filter,
        Err(_) => EnvFilter::try_new(level).map_err(|source| TelemetryError::Filter {
            level: level.to_string(),
            source,
        })?,
    };

    let json_layer = fmt::layer()
        .json()
        .with_current_span(true)
        .with_span_list(false)
        .with_target(true);

    tracing_subscriber::registry()
        .with(filter)
        .with(json_layer)
        .try_init()
        .map_err(|_| TelemetryError::AlreadyInitialized)
}

/// Placeholder when the `otel` feature is enabled: confirms the feature gate
/// compiles without pulling an OpenTelemetry SDK yet.
#[cfg(feature = "otel")]
pub fn init_otel_stub() {
    tracing::warn!(
        target: "ai_radar::otel",
        "OpenTelemetry export is not wired; built with feature `otel` as a compile gate only"
    );
}

// Tests intentionally omitted in T-159: `init_tracing` mutates global
// state (the `tracing` global default subscriber) and parallel tests
// would race against it. Coverage will arrive via integration tests
// once a dedicated test harness with serialized init is in place.
