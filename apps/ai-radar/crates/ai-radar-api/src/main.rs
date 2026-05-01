//! AI Radar — HTTP API binary entrypoint.
//!
//! Wires together configuration loading (figment env), JSON tracing,
//! the request-id middleware and the Axum router exposing `/health`.
//! Future epics extend the router with sources, items, digests, feedback,
//! metrics, etc. — see `docs/AI-RADAR-DECISIONS.md`.

#![forbid(unsafe_code)]
#![warn(clippy::pedantic)]

mod middleware;
mod router;
mod routes;

use std::net::SocketAddr;

use ai_radar_core::config::AppConfig;
use ai_radar_core::telemetry;
use anyhow::Context;
use tokio::net::TcpListener;
use tokio::signal;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    if cfg!(debug_assertions) {
        let _ = dotenvy::dotenv();
    }

    let config = AppConfig::from_env().context("failed to load configuration")?;
    telemetry::init_tracing(&config.log_level)
        .context("failed to initialize tracing subscriber")?;

    tracing::info!(
        version = ai_radar_core::VERSION,
        bind = %config.api_bind,
        "starting ai-radar-api"
    );

    let app = router::build_router();
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
