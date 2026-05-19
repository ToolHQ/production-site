//! Top-level router composition.
//!
//! Centralizes route mounting and middleware ordering. Two flavors:
//!
//! - [`build_router_no_state`]: stateless router used by `/health` only;
//!   handy for unit-testing the bootstrap before a database is wired in.
//! - [`build_router`]: the production router. Takes an [`AppState`] so
//!   handlers can reach the repositories.

use axum::middleware as axum_middleware;
use axum::Router;

use crate::middleware::request_id_middleware;
use crate::routes;
use crate::state::AppState;

/// Build a stateless router exposing `/health` only.
///
/// Used by `cargo test` so we can spin up the basic surface without
/// requiring a database connection.
#[cfg(test)]
pub fn build_router_no_state() -> Router {
    Router::new()
        .merge(routes::ui::router())
        .merge(routes::health::router())
        .layer(axum_middleware::from_fn(request_id_middleware))
}

/// Build the production router with shared state.
///
/// Middleware order matters: `request_id` is the outermost layer so
/// every downstream span and response carries the correlation id.
pub fn build_router(state: AppState) -> Router {
    let api = Router::new()
        .merge(routes::health::router())
        .merge(routes::health::ready_router())
        .merge(routes::metrics::router())
        .merge(routes::stats::router())
        .merge(routes::sources::router())
        .merge(routes::extract::router())
        .merge(routes::items::router())
        .merge(routes::score::router())
        .merge(routes::compare::router())
        .merge(routes::digest::router())
        .merge(routes::digests::router())
        .merge(routes::reports::router())
        .merge(routes::search::router())
        .with_state(state);

    Router::new()
        .merge(routes::ui::router())
        .merge(api)
        .layer(axum_middleware::from_fn(request_id_middleware))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;

    #[tokio::test]
    async fn health_is_reachable_through_full_router() {
        let app = build_router_no_state();

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/health")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
        let header = response
            .headers()
            .get(crate::middleware::request_id::REQUEST_ID_HEADER)
            .expect("middleware must echo request id")
            .to_str()
            .unwrap()
            .to_string();
        assert!(!header.is_empty());
    }

    #[tokio::test]
    async fn inbound_request_id_is_echoed() {
        let app = build_router_no_state();
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/health")
                    .header(
                        crate::middleware::request_id::REQUEST_ID_HEADER,
                        "test-trace-id",
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(
            response
                .headers()
                .get(crate::middleware::request_id::REQUEST_ID_HEADER)
                .unwrap(),
            "test-trace-id"
        );
    }
}
