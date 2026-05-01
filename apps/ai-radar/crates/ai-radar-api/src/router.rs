//! Top-level router composition.
//!
//! Centralizes route mounting and middleware ordering so the bootstrap
//! `main` stays small and tests can spin up the same router via
//! `oneshot`.

use axum::middleware as axum_middleware;
use axum::Router;

use crate::middleware::request_id_middleware;
use crate::routes;

/// Build the production router.
///
/// Middleware order matters: `request_id` is the outermost layer so every
/// downstream span and response carries the correlation id.
pub fn build_router() -> Router {
    Router::new()
        .merge(routes::health::router())
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
        let app = build_router();

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
        let app = build_router();
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
