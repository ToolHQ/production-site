//! AI Radar — HTTP API binary entrypoint.
//!
//! Wires together configuration loading (figment env), JSON tracing,
//! the request-id middleware, the database pool, the repositories
//! shared via `AppState`, and the Axum router exposing `/` (redirect),
//! `/health`, `/metrics`, `/sources`, `POST /extract/run`, and `POST /score/run`. Future epics extend the router with digests,
//! feedback, etc. — see `docs/AI-RADAR-DECISIONS.md`.

#![forbid(unsafe_code)]
#![warn(clippy::pedantic)]

mod error;
mod metrics_cache;
mod middleware;
mod router;
mod routes;
mod state;

use std::net::SocketAddr;
use std::sync::Arc;

use ai_radar_core::config::AppConfig;
use ai_radar_core::db::Database;
use ai_radar_core::metrics as radar_metrics;
use ai_radar_core::telemetry;
use anyhow::{anyhow, Context};
use metrics_exporter_prometheus::PrometheusBuilder;
use tokio::net::TcpListener;
use tokio::signal;

use crate::state::AppState;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    if cfg!(debug_assertions) {
        let _ = dotenvy::dotenv();
    }

    let config = AppConfig::from_env().context("failed to load configuration")?;
    telemetry::init_tracing(&config.log_level)
        .context("failed to initialize tracing subscriber")?;

    #[cfg(feature = "otel")]
    ai_radar_core::telemetry::init_otel_stub();

    ai_radar_core::langfuse_export::log_not_configured();

    let database_url = config
        .database_url
        .clone()
        .ok_or_else(|| anyhow!("DATABASE_URL is required to start the API (T-160 onwards)"))?;

    tracing::info!(
        version = ai_radar_core::VERSION,
        bind = %config.api_bind,
        "starting ai-radar-api"
    );

    let db = Database::connect(&database_url)
        .await
        .context("failed to connect to Postgres")?;
    db.migrate()
        .await
        .context("failed to run sqlx migrations")?;
    tracing::info!("postgres pool ready (migrations applied)");

    let prometheus = PrometheusBuilder::new()
        .install_recorder()
        .context("failed to install Prometheus metrics recorder")?;
    radar_metrics::describe_metrics();

    let state = AppState::new(db, prometheus, Arc::new(config.clone()));
    let app = router::build_router(state);

    let addr: SocketAddr = config
        .api_bind
        .parse()
        .with_context(|| format!("invalid AI_RADAR_API_BIND value: {}", config.api_bind))?;
    let listener = TcpListener::bind(addr)
        .await
        .with_context(|| format!("failed to bind {addr}"))?;

    tracing::info!(addr = %addr, "ai-radar-api listening");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .context("HTTP server error")?;

    tracing::info!("ai-radar-api shut down cleanly");
    Ok(())
}

async fn shutdown_signal() {
    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("failed to install SIGINT handler");
    };

    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("failed to install SIGTERM handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        () = ctrl_c => tracing::info!("received SIGINT, draining"),
        () = terminate => tracing::info!("received SIGTERM, draining"),
    }
}
