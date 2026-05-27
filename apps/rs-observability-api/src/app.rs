use super::*;
use axum::{
    extract::{Path as AxumPath, State},
    http::{header, HeaderValue, StatusCode},
    response::{Html, IntoResponse, Response},
    routing::get,
    Json, Router,
};

pub(super) fn build_app(state: AppState) -> Router {
    Router::new()
        .route("/", get(index))
        .route("/health", get(health))
        .route("/api/catalog", get(catalog))
        .route("/api/catalog/summary", get(catalog_summary))
        .route("/api/live/overview", get(live_overview))
        .route("/api/coroot-alerts", get(coroot_alerts))
        .route("/api/coroot-incidents", get(coroot_incidents))
        .route("/api/longhorn", get(longhorn_volumes))
        .route("/api/cronjobs", get(cronjobs))
        .route("/api/ingresses", get(ingresses))
        .route("/api/certificates", get(certificates))
        .route("/api/workloads", get(workloads))
        .route("/api/namespaces", get(namespaces))
        .route("/api/reports", get(report_index))
        .route("/artifacts/*path", get(artifact))
        // Assets estáticos do Vite — embutidos no binário via include_bytes!
        .route("/assets/app.js", get(asset_js))
        .route("/assets/app.css", get(asset_css))
        .route("/favicon.svg", get(favicon))
        .with_state(state)
}

async fn index() -> Html<&'static str> {
    Html(INDEX_HTML)
}

async fn asset_js() -> Response {
    let mut response = Response::new(ASSET_JS.into());
    response.headers_mut().insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("application/javascript; charset=utf-8"),
    );
    response.headers_mut().insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("public, max-age=31536000, immutable"),
    );
    response
}

async fn asset_css() -> Response {
    let mut response = Response::new(ASSET_CSS.into());
    response.headers_mut().insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("text/css; charset=utf-8"),
    );
    response.headers_mut().insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("public, max-age=31536000, immutable"),
    );
    response
}

async fn favicon() -> Response {
    let mut response = Response::new(FAVICON_SVG.into());
    response.headers_mut().insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("image/svg+xml"),
    );
    response.headers_mut().insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("public, max-age=86400"),
    );
    response
}

async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok",
        service: "rs-observability-api",
        live_cluster_api: state.live_monitor.is_some(),
        prometheus_metrics_api: true,
    })
}

async fn live_overview(State(state): State<AppState>) -> Response {
    let live_future = async {
        match &state.live_monitor {
            Some(monitor) => monitor.cached_or_refresh().await,
            None => unavailable_live_overview(
                "in-cluster Kubernetes API credentials are not available in this runtime",
            ),
        }
    };

    let (mut payload, node_metrics, honeypot) = tokio::join!(
        live_future,
        state.prometheus_monitor.fetch_node_metrics(),
        state.prometheus_monitor.fetch_honeypot_overview(),
    );

    payload.metrics = state
        .prometheus_monitor
        .cached_or_refresh(&payload.services)
        .await;
    payload.node_metrics = node_metrics;

    // Populate cluster property for existing OCI K8s nodes
    for node in &mut payload.nodes {
        node.cluster = "OCI-K8S".to_string();
    }

    // Inject secondary K8s cluster nodes (e.g., SSD-NODES kubeadm cluster).
    // These are tagged with the cluster name from external_nodes.json for metric correlation.
    let mut secondary_clusters: std::collections::HashSet<String> =
        std::collections::HashSet::new();
    if let Some(secondary) = &state.secondary_live_monitor {
        let secondary_overview =
            match tokio::time::timeout(Duration::from_secs(8), secondary.cached_or_refresh()).await
            {
                Ok(overview) => overview,
                Err(_) => {
                    eprintln!("secondary K8s refresh slow; using stale cache if available");
                    secondary
                        .overview_with_refresh_budget(Duration::from_millis(1))
                        .await
                }
            };
        if secondary_overview.available {
            for mut node in secondary_overview.nodes {
                // Match the cluster tag from external_nodes.json so Prometheus metrics correlate
                node.cluster = "SSD-NODES".to_string();
                node.ready = node_has_metrics(&node, &payload.node_metrics);
                secondary_clusters.insert(node.cluster.clone());
                payload.nodes.push(node);
            }
            payload.incidents.extend(secondary_overview.incidents);
        } else if let Some(error) = secondary_overview.error {
            eprintln!("secondary K8s monitor unavailable: {}", error);
        }
    }

    // Inject external physical nodes (Hetzner / SSD Nodes) — skip clusters already
    // covered by the secondary K8s monitor to avoid duplicate node entries.
    for mut node in state.prometheus_monitor.fetch_external_node_stats().await {
        if secondary_clusters.contains(&node.cluster) {
            continue;
        }
        node.ready = node_has_metrics(&node, &payload.node_metrics);
        payload.nodes.push(node);
    }

    // Re-sort the nodes list alphabetically by name
    payload.nodes.sort_by(|a, b| a.name.cmp(&b.name));

    payload.honeypot = honeypot;

    Json(payload).into_response()
}

async fn coroot_incidents(State(state): State<AppState>) -> Response {
    match &state.coroot_client {
        Some(client) => Json(client.fetch_incidents().await).into_response(),
        None => Json(crate::CorootIncidentsResponse {
            available: false,
            incidents: vec![],
            total: 0,
            queried_at_epoch: crate::unix_epoch_seconds(),
            error: Some(
                "Coroot client not configured (missing COROOT_EMAIL/COROOT_PASSWORD)".to_string(),
            ),
        })
        .into_response(),
    }
}

async fn coroot_alerts(State(state): State<AppState>) -> Response {
    match &state.coroot_client {
        Some(client) => Json(client.fetch_alerts().await).into_response(),
        None => Json(crate::CorootAlertsResponse {
            available: false,
            alerts: vec![],
            total: 0,
            queried_at_epoch: crate::unix_epoch_seconds(),
            error: Some(
                "Coroot client not configured (missing COROOT_EMAIL/COROOT_PASSWORD)".to_string(),
            ),
        })
        .into_response(),
    }
}

async fn longhorn_volumes(State(state): State<AppState>) -> Response {
    match &state.live_monitor {
        Some(monitor) => Json(monitor.fetch_longhorn().await).into_response(),
        None => Json(crate::LonghornResponse {
            available: false,
            volumes: vec![],
            total: 0,
            healthy: 0,
            degraded: 0,
            faulted: 0,
            queried_at_epoch: crate::unix_epoch_seconds(),
            error: Some(
                "In-cluster Kubernetes API credentials are not available in this runtime"
                    .to_string(),
            ),
        })
        .into_response(),
    }
}

async fn cronjobs(State(state): State<AppState>) -> Response {
    match &state.live_monitor {
        Some(monitor) => Json(monitor.fetch_cronjobs().await).into_response(),
        None => Json(crate::CronJobsResponse {
            available: false,
            cronjobs: vec![],
            total: 0,
            healthy: 0,
            failed: 0,
            queried_at_epoch: crate::unix_epoch_seconds(),
            error: Some(
                "In-cluster Kubernetes API credentials are not available in this runtime"
                    .to_string(),
            ),
        })
        .into_response(),
    }
}

async fn ingresses(State(state): State<AppState>) -> Response {
    match &state.live_monitor {
        Some(monitor) => Json(monitor.fetch_ingresses().await).into_response(),
        None => Json(crate::IngressesResponse {
            available: false,
            ingresses: vec![],
            total: 0,
            queried_at_epoch: crate::unix_epoch_seconds(),
            error: Some(
                "In-cluster Kubernetes API credentials are not available in this runtime"
                    .to_string(),
            ),
        })
        .into_response(),
    }
}

async fn certificates(State(state): State<AppState>) -> Response {
    match &state.live_monitor {
        Some(monitor) => Json(monitor.fetch_certificates().await).into_response(),
        None => Json(crate::CertificatesResponse {
            available: false,
            certificates: vec![],
            total: 0,
            expiring_soon: 0,
            critical: 0,
            queried_at_epoch: crate::unix_epoch_seconds(),
            error: Some(
                "In-cluster Kubernetes API credentials are not available in this runtime"
                    .to_string(),
            ),
        })
        .into_response(),
    }
}

async fn workloads(State(state): State<AppState>) -> Response {
    match &state.live_monitor {
        Some(monitor) => Json(monitor.fetch_workloads().await).into_response(),
        None => Json(crate::WorkloadsResponse {
            available: false,
            workloads: vec![],
            total: 0,
            healthy: 0,
            degraded: 0,
            down: 0,
            queried_at_epoch: crate::unix_epoch_seconds(),
            error: Some(
                "In-cluster Kubernetes API credentials are not available in this runtime"
                    .to_string(),
            ),
        })
        .into_response(),
    }
}

async fn namespaces(State(state): State<AppState>) -> Response {
    match &state.live_monitor {
        Some(monitor) => Json(monitor.fetch_namespaces().await).into_response(),
        None => Json(crate::NamespacesResponse {
            available: false,
            namespaces: vec![],
            total: 0,
            over_pressure: 0,
            queried_at_epoch: crate::unix_epoch_seconds(),
            error: Some(
                "In-cluster Kubernetes API credentials are not available in this runtime"
                    .to_string(),
            ),
        })
        .into_response(),
    }
}

async fn catalog(State(state): State<AppState>) -> Response {
    match read_json(&state, "latest-catalog/catalog.json").await {
        Ok(value) => Json(value).into_response(),
        Err(error) => json_error(
            StatusCode::SERVICE_UNAVAILABLE,
            "catalog unavailable",
            &error,
        ),
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

    Json(catalog_summary_from_catalog(&catalog)).into_response()
}

fn catalog_summary_from_catalog(catalog: &Value) -> CatalogSummary {
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
    let repo_only_app_count = repo_only
        .get("repo_only")
        .and_then(|value| value.get("apps"))
        .and_then(Value::as_array)
        .map(|items| items.len())
        .unwrap_or(0);
    let repo_only_component_count = repo_only
        .get("repo_only")
        .and_then(|value| value.get("components"))
        .and_then(Value::as_array)
        .map(|items| items.len())
        .unwrap_or(0);
    let cluster_only_count = repo_only
        .get("cluster_only")
        .and_then(Value::as_array)
        .map(|items| items.len())
        .unwrap_or(0);
    let undocumented_count = repo_only
        .get("gaps")
        .and_then(|value| value.get("no_docs"))
        .and_then(Value::as_array)
        .map(|items| items.len())
        .unwrap_or(0);
    let missing_deploy_script_count = repo_only
        .get("gaps")
        .and_then(|value| value.get("no_deploy_script"))
        .and_then(Value::as_array)
        .map(|items| items.len())
        .unwrap_or(0);

    let mut language_counts = BTreeMap::<String, usize>::new();
    let deployable_app_count = apps
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

    CatalogSummary {
        generated_at: catalog
            .get("generated_at")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        app_count: apps.len(),
        deployable_app_count,
        component_count: components.len(),
        cluster_workload_count: cluster_workloads.len(),
        repo_only_app_count,
        repo_only_component_count,
        cluster_only_count,
        undocumented_count,
        missing_deploy_script_count,
        app_languages: language_counts
            .into_iter()
            .map(|(language, count)| LanguageCount { language, count })
            .collect(),
    }
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
            return json_error(
                StatusCode::INTERNAL_SERVER_ERROR,
                "artifact read failed",
                &error.to_string(),
            );
        }
    };

    let content_type = content_type_for_path(&file_path);
    let mut response = Response::new(bytes.into());
    response
        .headers_mut()
        .insert(header::CONTENT_TYPE, HeaderValue::from_static(content_type));
    response
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{
        body::{to_bytes, Body},
        http::Request,
    };
    use serde_json::Value;
    use std::{
        env, fs,
        path::PathBuf,
        sync::Arc,
        time::{SystemTime, UNIX_EPOCH},
    };
    use tower::util::ServiceExt;

    fn create_reports_root(label: &str) -> PathBuf {
        let unique = format!(
            "{}-{}-{}",
            label,
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system clock before epoch")
                .as_nanos()
        );
        let root = env::temp_dir().join(unique);
        fs::create_dir_all(&root).expect("create temp reports root");
        root
    }

    fn cleanup_reports_root(root: &PathBuf) {
        let _ = fs::remove_dir_all(root);
    }

    fn test_state(reports_root: PathBuf) -> AppState {
        AppState {
            reports_root: Arc::new(reports_root),
            live_monitor: None,
            secondary_live_monitor: None,
            prometheus_monitor: Arc::new(PrometheusMonitor::new()),
            coroot_client: None,
        }
    }

    #[test]
    fn resolve_relative_path_rejects_escape_sequences() {
        let root = PathBuf::from("/tmp/reports-root");

        assert_eq!(
            crate::resolve_relative_path(&root, "/etc/passwd"),
            Err("absolute paths are not allowed".to_string())
        );
        assert_eq!(
            crate::resolve_relative_path(&root, "../secrets.txt"),
            Err("path traversal is not allowed".to_string())
        );
        assert_eq!(
            crate::resolve_relative_path(&root, "latest/inventory.html").expect("valid path"),
            root.join("latest/inventory.html")
        );
    }

    #[tokio::test]
    async fn health_route_reports_snapshot_mode() {
        let reports_root = create_reports_root("health-route");
        let app = build_app(test_state(reports_root.clone()));

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/health")
                    .body(Body::empty())
                    .expect("build request"),
            )
            .await
            .expect("route response");

        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("read response body");
        let payload: Value = serde_json::from_slice(&body).expect("decode health payload");

        assert_eq!(payload.get("status").and_then(Value::as_str), Some("ok"));
        assert_eq!(
            payload.get("service").and_then(Value::as_str),
            Some("rs-observability-api")
        );
        assert_eq!(
            payload.get("live_cluster_api").and_then(Value::as_bool),
            Some(false)
        );
        assert_eq!(
            payload
                .get("prometheus_metrics_api")
                .and_then(Value::as_bool),
            Some(true)
        );

        cleanup_reports_root(&reports_root);
    }

    #[tokio::test]
    async fn catalog_summary_route_reads_counts_from_reports_root() {
        let reports_root = create_reports_root("catalog-summary-route");
        let catalog_dir = reports_root.join("latest-catalog");
        fs::create_dir_all(&catalog_dir).expect("create latest-catalog dir");
        fs::write(
            catalog_dir.join("catalog.json"),
            serde_json::to_vec(&json!({
                "generated_at": "2026-04-21T12:00:00Z",
                "apps": [
                    {"name": "reports-api", "language": "rust", "deploy_readiness": "deployable"},
                    {"name": "reports-ui", "language": "typescript", "deploy_readiness": "deployable"},
                    {"name": "legacy-tool", "deploy_readiness": "draft"}
                ],
                "components": [
                    {"name": "nexus"},
                    {"name": "coroot"}
                ],
                "cluster": [
                    {"name": "postgres"}
                ],
                "crossReference": {
                    "repo_only": {
                        "apps": [{"name": "reports-ui"}],
                        "components": [{"name": "nexus"}]
                    },
                    "cluster_only": [{"name": "orphan-workload"}],
                    "gaps": {
                        "no_docs": [{"name": "legacy-tool"}],
                        "no_deploy_script": [{"name": "legacy-tool"}]
                    }
                }
            }))
            .expect("serialize sample catalog"),
        )
        .expect("write sample catalog");

        let app = build_app(test_state(reports_root.clone()));
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/catalog/summary")
                    .body(Body::empty())
                    .expect("build request"),
            )
            .await
            .expect("route response");

        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("read response body");
        let payload: Value = serde_json::from_slice(&body).expect("decode summary payload");

        assert_eq!(payload.get("app_count").and_then(Value::as_u64), Some(3));
        assert_eq!(
            payload.get("deployable_app_count").and_then(Value::as_u64),
            Some(2)
        );
        assert_eq!(
            payload.get("component_count").and_then(Value::as_u64),
            Some(2)
        );
        assert_eq!(
            payload
                .get("cluster_workload_count")
                .and_then(Value::as_u64),
            Some(1)
        );
        assert_eq!(
            payload.get("repo_only_app_count").and_then(Value::as_u64),
            Some(1)
        );
        assert_eq!(
            payload
                .get("repo_only_component_count")
                .and_then(Value::as_u64),
            Some(1)
        );
        assert_eq!(
            payload.get("cluster_only_count").and_then(Value::as_u64),
            Some(1)
        );
        assert_eq!(
            payload.get("undocumented_count").and_then(Value::as_u64),
            Some(1)
        );
        assert_eq!(
            payload
                .get("missing_deploy_script_count")
                .and_then(Value::as_u64),
            Some(1)
        );

        let languages = payload
            .get("app_languages")
            .and_then(Value::as_array)
            .expect("app_languages array");
        assert_eq!(languages.len(), 3);
        assert!(languages.iter().any(|entry| {
            entry.get("language").and_then(Value::as_str) == Some("rust")
                && entry.get("count").and_then(Value::as_u64) == Some(1)
        }));
        assert!(languages.iter().any(|entry| {
            entry.get("language").and_then(Value::as_str) == Some("typescript")
                && entry.get("count").and_then(Value::as_u64) == Some(1)
        }));
        assert!(languages.iter().any(|entry| {
            entry.get("language").and_then(Value::as_str) == Some("unknown")
                && entry.get("count").and_then(Value::as_u64) == Some(1)
        }));

        cleanup_reports_root(&reports_root);
    }
}
