use std::{
    env,
    net::SocketAddr,
    path::{Component, Path, PathBuf},
    sync::Arc,
};

use axum::{
    extract::{Path as AxumPath, State},
    http::{header, HeaderValue, StatusCode},
    response::{Html, IntoResponse, Response},
    routing::get,
    Json, Router,
};
use serde::Serialize;
use serde_json::{json, Value};

const INDEX_HTML: &str = include_str!("../web/index.html");

const KNOWN_REPORTS: &[(&str, &str, &str, &str)] = &[
    ("catalog-json", "Catalog JSON", "latest-catalog/catalog.json", "json"),
    ("catalog-html", "Catalog HTML", "latest-catalog/catalog.html", "html"),
    ("catalog-md", "Catalog Markdown", "latest-catalog/catalog.md", "markdown"),
    ("inventory-html", "Inventory HTML", "latest/inventory.html", "html"),
    ("inventory-md", "Inventory Markdown", "latest/inventory.md", "markdown"),
];

#[derive(Clone)]
struct AppState {
    reports_root: Arc<PathBuf>,
}

#[derive(Serialize)]
struct HealthResponse<'a> {
    status: &'a str,
    service: &'a str,
}

#[derive(Serialize)]
struct ReportArtifact {
    id: &'static str,
    label: &'static str,
    kind: &'static str,
    href: String,
    size_bytes: u64,
}

#[derive(Serialize)]
struct CatalogSummary {
    generated_at: Option<String>,
    app_count: usize,
    deployable_app_count: usize,
    component_count: usize,
    cluster_workload_count: usize,
    repo_only_app_count: usize,
    repo_only_component_count: usize,
    cluster_only_count: usize,
    undocumented_count: usize,
    missing_deploy_script_count: usize,
    app_languages: Vec<LanguageCount>,
}

#[derive(Serialize)]
struct LanguageCount {
    language: String,
    count: usize,
}

#[tokio::main]
async fn main() {
    let reports_root = resolve_reports_root();
    let port = env::var("PORT")
        .ok()
        .and_then(|value| value.parse::<u16>().ok())
        .unwrap_or(3000);

    let state = AppState {
        reports_root: Arc::new(reports_root),
    };

    let app = Router::new()
        .route("/", get(index))
        .route("/health", get(health))
        .route("/api/catalog", get(catalog))
        .route("/api/catalog/summary", get(catalog_summary))
        .route("/api/reports", get(report_index))
        .route("/artifacts/*path", get(artifact))
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    println!("rs-observability-api listening on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("bind listener");
    axum::serve(listener, app)
        .await
        .expect("serve axum app");
}

async fn index() -> Html<&'static str> {
    Html(INDEX_HTML)
}

async fn health() -> Json<HealthResponse<'static>> {
    Json(HealthResponse {
        status: "ok",
        service: "rs-observability-api",
    })
}

async fn catalog(State(state): State<AppState>) -> Response {
    match read_json(&state, "latest-catalog/catalog.json").await {
        Ok(value) => Json(value).into_response(),
        Err(error) => json_error(StatusCode::SERVICE_UNAVAILABLE, "catalog unavailable", &error),
    }
}

async fn catalog_summary(State(state): State<AppState>) -> Response {
    let catalog = match read_json(&state, "latest-catalog/catalog.json").await {
        Ok(value) => value,
        Err(error) => {
            return json_error(
                StatusCode::SERVICE_UNAVAILABLE,
                "catalog summary unavailable",
                &error,
            )
        }
    };

    let apps = catalog
        .get("apps")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let components = catalog
        .get("components")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let cluster_workloads = catalog
        .get("cluster")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let repo_only = catalog
        .get("crossReference")
        .or_else(|| catalog.get("cross_reference"))
        .unwrap_or(&Value::Null);
    let repo_only_apps = repo_only
        .get("repo_only")
        .and_then(|value| value.get("apps"))
        .and_then(Value::as_array)
        .map(|items| items.len())
        .unwrap_or(0);
    let repo_only_components = repo_only
        .get("repo_only")
        .and_then(|value| value.get("components"))
        .and_then(Value::as_array)
        .map(|items| items.len())
        .unwrap_or(0);
    let cluster_only = repo_only
        .get("cluster_only")
        .and_then(Value::as_array)
        .map(|items| items.len())
        .unwrap_or(0);
    let undocumented = repo_only
        .get("gaps")
        .and_then(|value| value.get("no_docs"))
        .and_then(Value::as_array)
        .map(|items| items.len())
        .unwrap_or(0);
    let missing_deploy_script = repo_only
        .get("gaps")
        .and_then(|value| value.get("no_deploy_script"))
        .and_then(Value::as_array)
        .map(|items| items.len())
        .unwrap_or(0);

    let mut language_counts = std::collections::BTreeMap::<String, usize>::new();
    let deployable_apps = apps
        .iter()
        .filter(|app| {
            app.get("deploy_readiness")
                .and_then(Value::as_str)
                .unwrap_or_default()
                == "deployable"
        })
        .count();

    for app in &apps {
        let language = app
            .get("language")
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .unwrap_or("unknown")
            .to_string();
        *language_counts.entry(language).or_insert(0) += 1;
    }

    let summary = CatalogSummary {
        generated_at: catalog
            .get("generated_at")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        app_count: apps.len(),
        deployable_app_count: deployable_apps,
        component_count: components.len(),
        cluster_workload_count: cluster_workloads.len(),
        repo_only_app_count: repo_only_apps,
        repo_only_component_count: repo_only_components,
        cluster_only_count: cluster_only,
        undocumented_count: undocumented,
        missing_deploy_script_count: missing_deploy_script,
        app_languages: language_counts
            .into_iter()
            .map(|(language, count)| LanguageCount { language, count })
            .collect(),
    };

    Json(summary).into_response()
}

async fn report_index(State(state): State<AppState>) -> Response {
    let mut artifacts = Vec::new();

    for (id, label, relative_path, kind) in KNOWN_REPORTS {
        let path = match resolve_relative_path(state.reports_root.as_ref(), relative_path) {
            Ok(path) => path,
            Err(_) => continue,
        };

        let metadata = match tokio::fs::metadata(&path).await {
            Ok(metadata) => metadata,
            Err(_) => continue,
        };

        if metadata.is_file() {
            artifacts.push(ReportArtifact {
                id,
                label,
                kind,
                href: format!("/artifacts/{}", relative_path),
                size_bytes: metadata.len(),
            });
        }
    }

    Json(json!({ "artifacts": artifacts })).into_response()
}

async fn artifact(State(state): State<AppState>, AxumPath(path): AxumPath<String>) -> Response {
    let file_path = match resolve_relative_path(state.reports_root.as_ref(), &path) {
        Ok(path) => path,
        Err(error) => {
            return json_error(StatusCode::BAD_REQUEST, "invalid artifact path", &error);
        }
    };

    let bytes = match tokio::fs::read(&file_path).await {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return json_error(StatusCode::NOT_FOUND, "artifact not found", &path);
        }
        Err(error) => {
            return json_error(StatusCode::INTERNAL_SERVER_ERROR, "artifact read failed", &error.to_string());
        }
    };

    let content_type = content_type_for_path(&file_path);
    let mut response = Response::new(bytes.into());
    response.headers_mut().insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static(content_type),
    );
    response
}

async fn read_json(state: &AppState, relative_path: &str) -> Result<Value, String> {
    let path = resolve_relative_path(state.reports_root.as_ref(), relative_path)?;
    let content = tokio::fs::read_to_string(path)
        .await
        .map_err(|error| error.to_string())?;
    serde_json::from_str(&content).map_err(|error| error.to_string())
}

fn resolve_relative_path(root: &Path, relative_path: &str) -> Result<PathBuf, String> {
    let candidate = PathBuf::from(relative_path);
    if candidate.is_absolute() {
        return Err("absolute paths are not allowed".to_string());
    }

    if candidate.components().any(|component| {
        matches!(component, Component::ParentDir | Component::RootDir | Component::Prefix(_))
    }) {
        return Err("path traversal is not allowed".to_string());
    }

    Ok(root.join(candidate))
}

fn resolve_reports_root() -> PathBuf {
    if let Ok(value) = env::var("REPORTS_ROOT") {
        return PathBuf::from(value);
    }

    let current_dir = env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let candidates = [
        current_dir.join("reports-bundle"),
        current_dir.join("../../reports"),
        PathBuf::from("/opt/reports"),
    ];

    candidates
        .into_iter()
        .find(|path| path.exists())
        .unwrap_or_else(|| PathBuf::from("/opt/reports"))
}

fn content_type_for_path(path: &Path) -> &'static str {
    match path.extension().and_then(|extension| extension.to_str()) {
        Some("json") => "application/json; charset=utf-8",
        Some("html") => "text/html; charset=utf-8",
        Some("md") => "text/markdown; charset=utf-8",
        _ => "application/octet-stream",
    }
}

fn json_error(status: StatusCode, message: &str, detail: &str) -> Response {
    (status, Json(json!({ "error": message, "detail": detail }))).into_response()
}
