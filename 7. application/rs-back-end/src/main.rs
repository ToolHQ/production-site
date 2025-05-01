use std::net::SocketAddr;

use axum::{
    middleware::{Next, from_fn},
    response::Response,
    body::Body,
    http::{Request, StatusCode},
    Json,
    routing::{get, post},
    Router
};
use serde::Serialize;
use serde_json::json;
use utoipa::{OpenApi, ToSchema};
use utoipa_swagger_ui::SwaggerUi;

mod logger;
mod middleware;
mod context;
mod parquet_handler;
mod parquet_convert;
mod heaptrack_report;

use rust_api::query;
use crate::logger::JsonLogger;
use crate::middleware::{RequestLoggerConfig, RequestLoggerLayer};
use crate::context::{with_context};

use crate::parquet_handler::{UploadForm, JsonRowResponse, upload_and_stream_parquet};
use crate::parquet_handler::__path_upload_and_stream_parquet;

use crate::parquet_convert::__path_convert_parquet_into_arrow;
use crate::parquet_convert::convert_parquet_into_arrow;
use crate::parquet_convert::__path_convert_arrow_into_ndjson;
use crate::parquet_convert::convert_arrow_into_ndjson;

use tower_http::limit::RequestBodyLimitLayer;
use tower::{ServiceBuilder};

const MAX_BYTES: usize = 50 * 1024 * 1024;

async fn log_413(req: Request<Body>, next: Next) -> Response {
    let res = next.run(req).await;
    if res.status() == StatusCode::PAYLOAD_TOO_LARGE {
        JsonLogger::new().error("Request payload too large", None);
    }
    res
}

#[utoipa::path(
    get,
    path = "/",
    tag = "General",
    responses((status = 200, description = "Hello World"))
)]
async fn hello_world() -> &'static str {
    with_context(|ctx| {
        println!("🧠 ctx: req_id={}, session_id={:?}", ctx.req_id.clone().unwrap_or_default(), ctx.session_id);
    });
    "Hello, world!"
}

#[utoipa::path(
    get,
    path = "/env",
    tag = "General",
    responses((status = 200, description = "Environment variables", body = EnvResponse))
)]
async fn env() -> Json<serde_json::Value> {
    let vars: std::collections::HashMap<String, String> = std::env::vars().collect();
    Json(serde_json::to_value(vars).unwrap())
}

#[utoipa::path(
    get,
    path = "/health",
    tag = "General",
    responses((status = 200, description = "API is healthy", body = HealthResponse))
)]
async fn health() -> Json<HealthResponse> {
    Json(HealthResponse { status: "ok" })
}

#[utoipa::path(
    get,
    path = "/db-test",
    tag = "Database",
    responses(
        (status = 200, description = "Test DB query", body = DbTestResponse),
        (status = 500, description = "Query error", body = ErrorResponse)
    )
)]
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

#[derive(Serialize, ToSchema)]
struct HealthResponse {
    status: &'static str,
}

#[derive(Serialize, ToSchema)]
struct DbTestResponse {
    result: serde_json::Value,
}

#[derive(Serialize, ToSchema)]
struct ErrorResponse {
    error: String,
}

#[derive(Serialize, ToSchema)]
struct EnvResponse {
    #[schema(value_type = Object)]
    env: serde_json::Value,
}

#[derive(OpenApi)]
#[openapi(
    info(
        title = "Rust API",
        version = "1.0.0",
        description = "A simple Rust API with Axum"
    ),
    servers(
        (url = "http://localhost:3002", description = "Local server")
    ),
    paths(
        hello_world,
        health,
        db_test_handler,
        env,
        upload_and_stream_parquet,
        convert_parquet_into_arrow,
        convert_arrow_into_ndjson,
    ),
    components(schemas(
        HealthResponse,
        DbTestResponse,
        ErrorResponse,
        EnvResponse,
        UploadForm,
        JsonRowResponse
    )),
    tags(
        (name = "General", description = "General endpoints"),
        (name = "Database", description = "PostgreSQL / Redshift testing"),
        (name = "Parquet", description = "Parquet upload and JSON streaming")
    )
)]
struct ApiDoc;

#[tokio::main]
async fn main() {
    let logger = JsonLogger::new();
    let request_logger_config = RequestLoggerConfig {
        routes_to_ignore: vec!["/health".to_string()],
        log_response_body: true,
    };

    let app = Router::new()
        .route("/", get(hello_world))
        .route("/health", get(health))
        .route("/db-test", get(db_test_handler))
        .route("/env", get(env))
        .route("/upload-parquet", post(upload_and_stream_parquet))
        .route("/convert-parquet-into-arrow", post(convert_parquet_into_arrow))
        .route("/convert-arrow-into-ndjson", post(convert_arrow_into_ndjson))
        .route_layer(
            ServiceBuilder::new()
                .layer(from_fn(log_413))
                .layer(RequestBodyLimitLayer::new(MAX_BYTES))
        )
        .merge(SwaggerUi::new("/swagger-ui").url("/api-doc/openapi.json", ApiDoc::openapi()))
        .merge(heaptrack_report::heaptrack_router())
        .layer(RequestLoggerLayer::new(logger.clone(), request_logger_config));

    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));
    println!("🚀 Server running at http://{}/", addr);

    axum::serve(tokio::net::TcpListener::bind(addr).await.unwrap(), app.into_make_service())
        .await
        .unwrap();
}
