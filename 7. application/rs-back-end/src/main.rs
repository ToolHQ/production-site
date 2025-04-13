use std::net::SocketAddr;

use axum::{routing::get, Router, Json};
use serde::Serialize;
use utoipa::{OpenApi, ToSchema};
use utoipa_swagger_ui::SwaggerUi;

mod logger;
mod middleware;
mod context;

use crate::logger::JsonLogger;
use crate::middleware::RequestLoggerLayer;
use crate::context::{with_context};

async fn hello_world() -> &'static str {
    with_context(|ctx| {
        println!("🧠 ctx: req_id={}, session_id={:?}", ctx.req_id.clone().unwrap_or_default(), ctx.session_id);
    });
    "Hello, world!"
}

#[derive(Serialize, ToSchema)]
struct HealthResponse {
    status: &'static str,
}

#[utoipa::path(
    get,
    path = "/health",
    responses((status = 200, description = "API is healthy", body = HealthResponse))
)]
async fn health() -> Json<HealthResponse> {
    // JsonLogger::new().info("Health check endpoint hit", None);
    Json(HealthResponse { status: "ok" })
}

#[derive(OpenApi)]
#[openapi(paths(health), components(schemas(HealthResponse)))]
struct ApiDoc;

#[tokio::main]
async fn main() {
    let logger = JsonLogger::new();

    let app = Router::new()
        .route("/", get(hello_world))
        .route("/health", get(health))
        .merge(SwaggerUi::new("/swagger-ui").url("/api-doc/openapi.json", ApiDoc::openapi()))
        .layer(RequestLoggerLayer::new(logger.clone()));

    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));
    println!("🚀 Server running at http://{}/", addr);

    axum::serve(tokio::net::TcpListener::bind(addr).await.unwrap(), app.into_make_service())
        .await
        .unwrap();
}
