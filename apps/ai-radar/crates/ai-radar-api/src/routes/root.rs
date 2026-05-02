//! Root path — browsers open `/`; we redirect to `/health` for a useful JSON payload.

use axum::response::Redirect;
use axum::routing::get;
use axum::Router;

/// `GET /` → temporary redirect to [`/health`](crate::routes::health).
pub fn router<S>() -> Router<S>
where
    S: Clone + Send + Sync + 'static,
{
    Router::new().route("/", get(|| async { Redirect::temporary("/health") }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;

    #[tokio::test]
    async fn root_redirects_to_health() {
        let app: Router<()> = router();

        let response = app
            .oneshot(Request::builder().uri("/").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::TEMPORARY_REDIRECT);
        assert_eq!(
            response
                .headers()
                .get(axum::http::header::LOCATION)
                .unwrap(),
            "/health"
        );
    }
}
