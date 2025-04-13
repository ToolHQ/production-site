use std::net::SocketAddr;

use axum::{routing::get, Router, Json};
use serde::Serialize;
use serde_json::json;
use utoipa::{OpenApi, ToSchema};
use utoipa_swagger_ui::SwaggerUi;

mod logger;
mod middleware;
mod context;

use rust_api::query;
use crate::logger::JsonLogger;
use crate::middleware::{RequestLoggerConfig, RequestLoggerLayer};
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

async fn db_test_handler() -> Json<serde_json::Value> {
    let bindings = json!({});
    match query("SELECT JSONB_BUILD_OBJECT('t', 1 + 1) as result", Some(bindings)).await {
        Ok(rows) => {
            if let Some(row) = rows.get(0) {
                Json(json!({ "result": row }))
            } else {
                Json(json!({ "error": "No rows returned" }))
            }
        }
        Err(err) => Json(json!({ "error": err.to_string() })),
    }
}

#[tokio::main]
async fn main() {
    let logger = JsonLogger::new();
    let request_logger_config = RequestLoggerConfig {
        routes_to_ignore: vec!["/health".to_string()],
        log_response_body: false,
    };
    // rust_api::set_listener(|event, ctx| {
    //     let logger = JsonLogger::new(); // or inject file/line explicitly
    //     logger.info(&event, ctx);
    // });

    let app = Router::new()
        .route("/", get(hello_world))
        .route("/health", get(health))
        .route("/db-test", get(db_test_handler))
        .route("/env", get(|| async {
            let vars: std::collections::HashMap<String, String> = std::env::vars().collect();
            Json(serde_json::to_value(vars).unwrap())
        }))
        .merge(SwaggerUi::new("/swagger-ui").url("/api-doc/openapi.json", ApiDoc::openapi()))
        .layer(RequestLoggerLayer::new(logger.clone(), request_logger_config));

    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));
    println!("🚀 Server running at http://{}/", addr);

    axum::serve(tokio::net::TcpListener::bind(addr).await.unwrap(), app.into_make_service())
        .await
        .unwrap();
}
