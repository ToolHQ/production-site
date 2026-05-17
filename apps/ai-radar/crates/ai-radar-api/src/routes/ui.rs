//! Operator console — static HTML/CSS/JS served from embedded assets (**T-175**).
//!
//! SPA shell at `GET /`; API JSON routes (`/digests`, `/sources`, …) unchanged.

use axum::http::{header, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::Router;
use include_dir::{include_dir, Dir};

static ASSETS: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/assets");

/// Console routes (no `AppState` required).
pub fn router() -> Router {
    Router::new()
        .route("/", get(|| serve_file("index.html", "text/html; charset=utf-8")))
        .route(
            "/assets/app.css",
            get(|| serve_file("app.css", "text/css; charset=utf-8")),
        )
        .route(
            "/assets/app.js",
            get(|| serve_file("app.js", "application/javascript; charset=utf-8")),
        )
        .route(
            "/assets/favicon.svg",
            get(|| serve_file("favicon.svg", "image/svg+xml")),
        )
}

async fn serve_file(path: &str, content_type: &'static str) -> Response {
    match ASSETS.get_file(path) {
        Some(file) => (
            StatusCode::OK,
            [(header::CONTENT_TYPE, content_type)],
            file.contents().to_vec(),
        )
            .into_response(),
        None => (StatusCode::NOT_FOUND, "not found").into_response(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::Request;
    use tower::ServiceExt;

    #[tokio::test]
    async fn favicon_is_svg() {
        let app = router();
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/assets/favicon.svg")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
        let ct = response
            .headers()
            .get(header::CONTENT_TYPE)
            .unwrap()
            .to_str()
            .unwrap();
        assert_eq!(ct, "image/svg+xml");
    }

    #[tokio::test]
    async fn index_is_html() {
        let app = router();
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
        let ct = response
            .headers()
            .get(header::CONTENT_TYPE)
            .unwrap()
            .to_str()
            .unwrap();
        assert!(ct.starts_with("text/html"));
    }
}
