use std::{
    collections::{BTreeMap, BTreeSet},
    env,
    net::SocketAddr,
    path::{Component, Path, PathBuf},
    sync::Arc,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use axum::{
    extract::{Path as AxumPath, State},
    http::{header, HeaderValue, StatusCode},
    response::{Html, IntoResponse, Response},
    routing::get,
    Json, Router,
};
use reqwest::{
    header::{HeaderMap, HeaderValue as ReqwestHeaderValue, ACCEPT, AUTHORIZATION},
    Certificate, Client,
};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::sync::RwLock;

const INDEX_HTML: &str = include_str!("../web/index.html");
const LIVE_CACHE_TTL: Duration = Duration::from_secs(10);
const LIVE_REFRESH_INTERVAL_SECONDS: u64 = 15;

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
    live_monitor: Option<Arc<LiveMonitor>>,
}

#[derive(Clone)]
struct LiveMonitor {
    client: Client,
    base_url: String,
    cache: Arc<RwLock<Option<CachedLiveOverview>>>,
}

#[derive(Clone)]
struct CachedLiveOverview {
    fetched_at: Instant,
    payload: LiveOverview,
}

#[derive(Serialize)]
struct HealthResponse {
    status: &'static str,
    service: &'static str,
    live_cluster_api: bool,
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

#[derive(Serialize, Clone)]
struct LiveOverview {
    available: bool,
    stale: bool,
    source: &'static str,
    refreshed_at_epoch: u64,
    refresh_interval_seconds: u64,
    summary: LiveSummary,
    services: Vec<LiveService>,
    incidents: Vec<LiveIncident>,
    error: Option<String>,
}

#[derive(Serialize, Clone, Default)]
struct LiveSummary {
    critical_services: usize,
    healthy_services: usize,
    degraded_services: usize,
    down_services: usize,
    total_pods: usize,
    running_pods: usize,
    restarting_pods: usize,
    nodes_ready: usize,
    nodes_total: usize,
    affected_namespaces: usize,
}

#[derive(Serialize, Clone)]
struct LiveService {
    id: &'static str,
    label: &'static str,
    namespace: &'static str,
    workload_kind: &'static str,
    workload_name: String,
    route: Option<String>,
    status: String,
    message: String,
    desired: i32,
    ready: i32,
    available: i32,
    pods_total: usize,
    pods_ready: usize,
    running_pods: usize,
    restart_count: i32,
}

#[derive(Serialize, Clone)]
struct LiveIncident {
    severity: &'static str,
    namespace: String,
    resource: String,
    message: String,
}

#[derive(Copy, Clone)]
enum TargetKind {
    Deployment,
    StatefulSet,
    DaemonSet,
}

impl TargetKind {
    fn as_str(self) -> &'static str {
        match self {
            Self::Deployment => "deployment",
            Self::StatefulSet => "statefulset",
            Self::DaemonSet => "daemonset",
        }
    }
}

#[derive(Copy, Clone)]
struct ServiceTarget {
    id: &'static str,
    label: &'static str,
    namespace: &'static str,
    kind: TargetKind,
    name: &'static str,
    route: Option<&'static str>,
}

#[derive(Deserialize, Clone, Default)]
struct KubeList<T> {
    #[serde(default)]
    items: Vec<T>,
}

#[derive(Deserialize, Clone, Default)]
struct ObjectMeta {
    name: Option<String>,
    namespace: Option<String>,
    #[serde(default)]
    labels: BTreeMap<String, String>,
}

#[derive(Deserialize, Clone, Default)]
struct LabelSelector {
    #[serde(default, rename = "matchLabels")]
    match_labels: BTreeMap<String, String>,
}

#[derive(Deserialize, Clone, Default)]
struct WorkloadSpec {
    selector: Option<LabelSelector>,
    replicas: Option<i32>,
}

#[derive(Deserialize, Clone, Default)]
struct DeploymentResource {
    #[serde(default)]
    metadata: ObjectMeta,
    spec: Option<WorkloadSpec>,
    status: Option<DeploymentStatus>,
}

#[derive(Deserialize, Clone, Default)]
struct DeploymentStatus {
    replicas: Option<i32>,
    #[serde(rename = "readyReplicas")]
    ready_replicas: Option<i32>,
    #[serde(rename = "availableReplicas")]
    available_replicas: Option<i32>,
}

#[derive(Deserialize, Clone, Default)]
struct StatefulSetResource {
    #[serde(default)]
    metadata: ObjectMeta,
    spec: Option<WorkloadSpec>,
    status: Option<StatefulSetStatus>,
}

#[derive(Deserialize, Clone, Default)]
struct StatefulSetStatus {
    replicas: Option<i32>,
    #[serde(rename = "readyReplicas")]
    ready_replicas: Option<i32>,
    #[serde(rename = "currentReplicas")]
    current_replicas: Option<i32>,
}

#[derive(Deserialize, Clone, Default)]
struct DaemonSetResource {
    #[serde(default)]
    metadata: ObjectMeta,
    spec: Option<DaemonSetSpec>,
    status: Option<DaemonSetStatus>,
}

#[derive(Deserialize, Clone, Default)]
struct DaemonSetSpec {
    selector: Option<LabelSelector>,
}

#[derive(Deserialize, Clone, Default)]
struct DaemonSetStatus {
    #[serde(rename = "desiredNumberScheduled")]
    desired_number_scheduled: Option<i32>,
    #[serde(rename = "numberReady")]
    number_ready: Option<i32>,
    #[serde(rename = "numberAvailable")]
    number_available: Option<i32>,
}

#[derive(Deserialize, Clone, Default)]
struct PodResource {
    #[serde(default)]
    metadata: ObjectMeta,
    status: Option<PodStatus>,
}

#[derive(Deserialize, Clone, Default)]
struct PodStatus {
    phase: Option<String>,
    reason: Option<String>,
    #[serde(default, rename = "containerStatuses")]
    container_statuses: Vec<ContainerStatus>,
}

#[derive(Deserialize, Clone, Default)]
struct ContainerStatus {
    ready: bool,
    #[serde(default, rename = "restartCount")]
    restart_count: i32,
    state: Option<ContainerState>,
}

#[derive(Deserialize, Clone, Default)]
struct ContainerState {
    waiting: Option<ContainerStateDetail>,
    terminated: Option<ContainerStateDetail>,
}

#[derive(Deserialize, Clone, Default)]
struct ContainerStateDetail {
    reason: Option<String>,
}

#[derive(Deserialize, Clone, Default)]
struct NodeResource {
    #[serde(default)]
    metadata: ObjectMeta,
    status: Option<NodeStatus>,
}

#[derive(Deserialize, Clone, Default)]
struct NodeStatus {
    #[serde(default)]
    conditions: Vec<NodeCondition>,
}

#[derive(Deserialize, Clone, Default)]
struct NodeCondition {
    #[serde(rename = "type")]
    type_name: Option<String>,
    status: Option<String>,
}

#[derive(Default)]
struct PodRollup {
    total: usize,
    ready: usize,
    running: usize,
    restart_count: i32,
    has_blocker: bool,
    issue: Option<String>,
}

#[tokio::main]
async fn main() {
    let reports_root = resolve_reports_root();
    let port = env::var("PORT")
        .ok()
        .and_then(|value| value.parse::<u16>().ok())
        .unwrap_or(3000);
    let live_monitor = match LiveMonitor::new().await {
        Ok(monitor) => Some(Arc::new(monitor)),
        Err(error) => {
            eprintln!("live monitor disabled: {}", error);
            None
        }
    };

    let state = AppState {
        reports_root: Arc::new(reports_root),
        live_monitor,
    };

    let app = Router::new()
        .route("/", get(index))
        .route("/health", get(health))
        .route("/api/catalog", get(catalog))
        .route("/api/catalog/summary", get(catalog_summary))
        .route("/api/live/overview", get(live_overview))
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

async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok",
        service: "rs-observability-api",
        live_cluster_api: state.live_monitor.is_some(),
    })
}

async fn live_overview(State(state): State<AppState>) -> Response {
    let payload = match state.live_monitor {
        Some(monitor) => monitor.cached_or_refresh().await,
        None => unavailable_live_overview(
            "in-cluster Kubernetes API credentials are not available in this runtime",
        ),
    };

    Json(payload).into_response()
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

impl LiveMonitor {
    async fn new() -> Result<Self, String> {
        let host = env::var("KUBERNETES_SERVICE_HOST")
            .map_err(|_| "KUBERNETES_SERVICE_HOST is not set".to_string())?;
        let port = env::var("KUBERNETES_SERVICE_PORT_HTTPS")
            .or_else(|_| env::var("KUBERNETES_SERVICE_PORT"))
            .unwrap_or_else(|_| "443".to_string());
        let token = tokio::fs::read_to_string(
            "/var/run/secrets/kubernetes.io/serviceaccount/token",
        )
        .await
        .map_err(|error| format!("read service account token: {}", error))?;
        let cluster_ca = tokio::fs::read(
            "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt",
        )
        .await
        .map_err(|error| format!("read cluster CA: {}", error))?;
        let certificate = Certificate::from_pem(&cluster_ca)
            .map_err(|error| format!("parse cluster CA: {}", error))?;

        let mut headers = HeaderMap::new();
        headers.insert(ACCEPT, ReqwestHeaderValue::from_static("application/json"));
        let auth_value = format!("Bearer {}", token.trim());
        headers.insert(
            AUTHORIZATION,
            ReqwestHeaderValue::from_str(&auth_value)
                .map_err(|error| format!("build auth header: {}", error))?,
        );

        let client = Client::builder()
            .use_rustls_tls()
            .add_root_certificate(certificate)
            .default_headers(headers)
            .build()
            .map_err(|error| format!("build Kubernetes client: {}", error))?;

        Ok(Self {
            client,
            base_url: format!("https://{}:{}", host, port),
            cache: Arc::new(RwLock::new(None)),
        })
    }

    async fn cached_or_refresh(&self) -> LiveOverview {
        if let Some(payload) = self.fresh_cache().await {
            return payload;
        }

        match self.fetch_live().await {
            Ok(payload) => {
                *self.cache.write().await = Some(CachedLiveOverview {
                    fetched_at: Instant::now(),
                    payload: payload.clone(),
                });
                payload
            }
            Err(error) => {
                if let Some(mut stale_payload) = self.cached_payload().await {
                    stale_payload.stale = true;
                    stale_payload.error = Some(error);
                    stale_payload
                } else {
                    unavailable_live_overview(error)
                }
            }
        }
    }

    async fn fresh_cache(&self) -> Option<LiveOverview> {
        let guard = self.cache.read().await;
        guard.as_ref().and_then(|entry| {
            if entry.fetched_at.elapsed() < LIVE_CACHE_TTL {
                Some(entry.payload.clone())
            } else {
                None
            }
        })
    }

    async fn cached_payload(&self) -> Option<LiveOverview> {
        let guard = self.cache.read().await;
        guard.as_ref().map(|entry| entry.payload.clone())
    }

    async fn fetch_live(&self) -> Result<LiveOverview, String> {
        let (deployments, statefulsets, daemonsets, pods, nodes) = tokio::join!(
            self.fetch_json::<KubeList<DeploymentResource>>("/apis/apps/v1/deployments"),
            self.fetch_json::<KubeList<StatefulSetResource>>("/apis/apps/v1/statefulsets"),
            self.fetch_json::<KubeList<DaemonSetResource>>("/apis/apps/v1/daemonsets"),
            self.fetch_json::<KubeList<PodResource>>("/api/v1/pods"),
            self.fetch_json::<KubeList<NodeResource>>("/api/v1/nodes"),
        );

        let deployments = deployments?;
        let statefulsets = statefulsets?;
        let daemonsets = daemonsets?;
        let pods = pods?;
        let nodes = nodes?;

        let services = build_live_services(
            &deployments.items,
            &statefulsets.items,
            &daemonsets.items,
            &pods.items,
        );
        let incidents = build_live_incidents(&pods.items, &nodes.items);
        let summary = build_live_summary(&services, &pods.items, &nodes.items);

        Ok(LiveOverview {
            available: true,
            stale: false,
            source: "in-cluster-api",
            refreshed_at_epoch: unix_epoch_seconds(),
            refresh_interval_seconds: LIVE_REFRESH_INTERVAL_SECONDS,
            summary,
            services,
            incidents,
            error: None,
        })
    }

    async fn fetch_json<T>(&self, path: &str) -> Result<T, String>
    where
        T: DeserializeOwned,
    {
        let url = format!("{}{}", self.base_url, path);
        let response = self
            .client
            .get(url)
            .send()
            .await
            .map_err(|error| format!("request cluster API: {}", error))?;
        let response = response
            .error_for_status()
            .map_err(|error| format!("cluster API status error: {}", error))?;
        response
            .json::<T>()
            .await
            .map_err(|error| format!("decode cluster API payload: {}", error))
    }
}

fn content_type_for_path(path: &Path) -> &'static str {
    match path.extension().and_then(|extension| extension.to_str()) {
        Some("json") => "application/json; charset=utf-8",
        Some("html") => "text/html; charset=utf-8",
        Some("md") => "text/markdown; charset=utf-8",
        _ => "application/octet-stream",
    }
}

fn build_live_services(
    deployments: &[DeploymentResource],
    statefulsets: &[StatefulSetResource],
    daemonsets: &[DaemonSetResource],
    pods: &[PodResource],
) -> Vec<LiveService> {
    service_targets()
        .into_iter()
        .map(|target| match target.kind {
            TargetKind::Deployment => deployments
                .iter()
                .find(|item| matches_name(&item.metadata, target.namespace, target.name))
                .map(|item| {
                    let selector = item
                        .spec
                        .as_ref()
                        .and_then(|spec| spec.selector.as_ref())
                        .map(|selector| selector.match_labels.clone())
                        .unwrap_or_default();
                    build_live_service(
                        target,
                        item.spec
                            .as_ref()
                            .and_then(|spec| spec.replicas)
                            .or_else(|| item.status.as_ref().and_then(|status| status.replicas))
                            .unwrap_or(1),
                        item.status
                            .as_ref()
                            .and_then(|status| status.ready_replicas)
                            .unwrap_or(0),
                        item.status
                            .as_ref()
                            .and_then(|status| status.available_replicas)
                            .unwrap_or(0),
                        selector,
                        pods,
                    )
                })
                .unwrap_or_else(|| missing_live_service(target)),
            TargetKind::StatefulSet => statefulsets
                .iter()
                .find(|item| matches_name(&item.metadata, target.namespace, target.name))
                .map(|item| {
                    let selector = item
                        .spec
                        .as_ref()
                        .and_then(|spec| spec.selector.as_ref())
                        .map(|selector| selector.match_labels.clone())
                        .unwrap_or_default();
                    build_live_service(
                        target,
                        item.spec
                            .as_ref()
                            .and_then(|spec| spec.replicas)
                            .or_else(|| item.status.as_ref().and_then(|status| status.replicas))
                            .unwrap_or(1),
                        item.status
                            .as_ref()
                            .and_then(|status| status.ready_replicas)
                            .unwrap_or(0),
                        item.status
                            .as_ref()
                            .and_then(|status| status.current_replicas)
                            .or_else(|| item.status.as_ref().and_then(|status| status.ready_replicas))
                            .unwrap_or(0),
                        selector,
                        pods,
                    )
                })
                .unwrap_or_else(|| missing_live_service(target)),
            TargetKind::DaemonSet => daemonsets
                .iter()
                .find(|item| matches_name(&item.metadata, target.namespace, target.name))
                .map(|item| {
                    let selector = item
                        .spec
                        .as_ref()
                        .and_then(|spec| spec.selector.as_ref())
                        .map(|selector| selector.match_labels.clone())
                        .unwrap_or_default();
                    build_live_service(
                        target,
                        item.status
                            .as_ref()
                            .and_then(|status| status.desired_number_scheduled)
                            .unwrap_or(0),
                        item.status
                            .as_ref()
                            .and_then(|status| status.number_ready)
                            .unwrap_or(0),
                        item.status
                            .as_ref()
                            .and_then(|status| status.number_available)
                            .unwrap_or(0),
                        selector,
                        pods,
                    )
                })
                .unwrap_or_else(|| missing_live_service(target)),
        })
        .collect()
}

fn build_live_service(
    target: ServiceTarget,
    desired: i32,
    ready: i32,
    available: i32,
    selector: BTreeMap<String, String>,
    pods: &[PodResource],
) -> LiveService {
    let matching_pods = pods_for_target(pods, target.namespace, &selector, target.name);
    let rollup = rollup_pods(&matching_pods);

    let mut status = if desired > 0 && ready >= desired && available >= desired && !rollup.has_blocker {
        "healthy"
    } else if ready > 0 || rollup.running > 0 {
        "degraded"
    } else {
        "down"
    };

    let mut message = if let Some(issue) = rollup.issue.clone() {
        issue
    } else {
        format!("{} of {} replicas ready", ready, desired.max(1))
    };

    if status == "healthy" && rollup.restart_count > 0 {
        status = "degraded";
        message = format!(
            "{} restarts observed across {} pod{}",
            rollup.restart_count,
            rollup.total,
            if rollup.total == 1 { "" } else { "s" }
        );
    }

    LiveService {
        id: target.id,
        label: target.label,
        namespace: target.namespace,
        workload_kind: target.kind.as_str(),
        workload_name: target.name.to_string(),
        route: target.route.map(ToOwned::to_owned),
        status: status.to_string(),
        message,
        desired,
        ready,
        available,
        pods_total: rollup.total,
        pods_ready: rollup.ready,
        running_pods: rollup.running,
        restart_count: rollup.restart_count,
    }
}

fn missing_live_service(target: ServiceTarget) -> LiveService {
    LiveService {
        id: target.id,
        label: target.label,
        namespace: target.namespace,
        workload_kind: target.kind.as_str(),
        workload_name: target.name.to_string(),
        route: target.route.map(ToOwned::to_owned),
        status: "down".to_string(),
        message: "workload not found in cluster API".to_string(),
        desired: 0,
        ready: 0,
        available: 0,
        pods_total: 0,
        pods_ready: 0,
        running_pods: 0,
        restart_count: 0,
    }
}

fn build_live_incidents(pods: &[PodResource], nodes: &[NodeResource]) -> Vec<LiveIncident> {
    let namespaces = tracked_namespaces();
    let mut incidents = Vec::new();

    for node in nodes {
        if !is_node_ready(node) {
            incidents.push(LiveIncident {
                severity: "critical",
                namespace: "cluster".to_string(),
                resource: node_name(node).to_string(),
                message: "node is not Ready".to_string(),
            });
        }
    }

    for pod in pods.iter().filter(|pod| {
        namespaces.contains(pod.metadata.namespace.as_deref().unwrap_or_default())
    }) {
        if let Some((severity, message)) = incident_for_pod(pod) {
            incidents.push(LiveIncident {
                severity,
                namespace: pod.metadata.namespace.clone().unwrap_or_else(|| "unknown".to_string()),
                resource: pod_name(pod).to_string(),
                message,
            });
        }
    }

    incidents.sort_by_key(|incident| incident_rank(incident.severity));
    incidents.truncate(8);
    incidents
}

fn build_live_summary(
    services: &[LiveService],
    pods: &[PodResource],
    nodes: &[NodeResource],
) -> LiveSummary {
    let namespaces = tracked_namespaces();
    let tracked_pods: Vec<&PodResource> = pods
        .iter()
        .filter(|pod| namespaces.contains(pod.metadata.namespace.as_deref().unwrap_or_default()))
        .collect();

    LiveSummary {
        critical_services: services.len(),
        healthy_services: services.iter().filter(|service| service.status == "healthy").count(),
        degraded_services: services.iter().filter(|service| service.status == "degraded").count(),
        down_services: services.iter().filter(|service| service.status == "down").count(),
        total_pods: tracked_pods.len(),
        running_pods: tracked_pods
            .iter()
            .filter(|pod| pod_phase(pod) == "Running")
            .count(),
        restarting_pods: tracked_pods
            .iter()
            .filter(|pod| pod_restart_count(pod) > 0)
            .count(),
        nodes_ready: nodes.iter().filter(|node| is_node_ready(node)).count(),
        nodes_total: nodes.len(),
        affected_namespaces: namespaces.len(),
    }
}

fn tracked_namespaces() -> BTreeSet<&'static str> {
    service_targets()
        .into_iter()
        .map(|target| target.namespace)
        .collect()
}

fn service_targets() -> [ServiceTarget; 6] {
    [
        ServiceTarget {
            id: "ingress-edge",
            label: "Ingress Edge",
            namespace: "ingress-nginx",
            kind: TargetKind::Deployment,
            name: "ingress-nginx-controller",
            route: Some("*.dnor.io"),
        },
        ServiceTarget {
            id: "nexus-registry",
            label: "Nexus Registry",
            namespace: "nexus",
            kind: TargetKind::Deployment,
            name: "nexus-deployment",
            route: Some("nexus.dnor.io"),
        },
        ServiceTarget {
            id: "postgres-ha",
            label: "Postgres HA",
            namespace: "postgres",
            kind: TargetKind::StatefulSet,
            name: "postgres",
            route: Some("postgres-service"),
        },
        ServiceTarget {
            id: "coroot-ui",
            label: "Coroot UI",
            namespace: "coroot",
            kind: TargetKind::Deployment,
            name: "coroot",
            route: Some("coroot.dnor.io"),
        },
        ServiceTarget {
            id: "coroot-prometheus",
            label: "Coroot Prometheus",
            namespace: "coroot",
            kind: TargetKind::Deployment,
            name: "coroot-prometheus-server",
            route: None,
        },
        ServiceTarget {
            id: "longhorn-manager",
            label: "Longhorn Manager",
            namespace: "longhorn-system",
            kind: TargetKind::DaemonSet,
            name: "longhorn-manager",
            route: Some("longhorn.dnor.io"),
        },
    ]
}

fn matches_name(metadata: &ObjectMeta, namespace: &str, name: &str) -> bool {
    metadata.namespace.as_deref() == Some(namespace) && metadata.name.as_deref() == Some(name)
}

fn pods_for_target<'a>(
    pods: &'a [PodResource],
    namespace: &str,
    selector: &BTreeMap<String, String>,
    workload_name: &str,
) -> Vec<&'a PodResource> {
    let mut matches: Vec<&PodResource> = pods
        .iter()
        .filter(|pod| {
            pod.metadata.namespace.as_deref() == Some(namespace)
                && !selector.is_empty()
                && selector_matches(&pod.metadata.labels, selector)
        })
        .collect();

    if matches.is_empty() {
        matches = pods
            .iter()
            .filter(|pod| {
                pod.metadata.namespace.as_deref() == Some(namespace)
                    && pod_name(pod).starts_with(workload_name)
            })
            .collect();
    }

    matches
        .into_iter()
        .filter(|pod| !is_terminal_pod(pod))
        .collect()
}

fn selector_matches(labels: &BTreeMap<String, String>, selector: &BTreeMap<String, String>) -> bool {
    selector
        .iter()
        .all(|(key, value)| labels.get(key).map(String::as_str) == Some(value.as_str()))
}

fn rollup_pods(pods: &[&PodResource]) -> PodRollup {
    let mut rollup = PodRollup {
        total: pods.len(),
        ..PodRollup::default()
    };

    for pod in pods {
        let phase = pod_phase(pod);
        let container_statuses = pod
            .status
            .as_ref()
            .map(|status| status.container_statuses.as_slice())
            .unwrap_or(&[]);

        if phase == "Running" {
            rollup.running += 1;
        }
        if phase == "Running" && !container_statuses.is_empty() && container_statuses.iter().all(|status| status.ready) {
            rollup.ready += 1;
        }

        rollup.restart_count += container_statuses
            .iter()
            .map(|status| status.restart_count)
            .sum::<i32>();

        if let Some(issue) = pod_issue(pod) {
            rollup.has_blocker = true;
            if rollup.issue.is_none() {
                rollup.issue = Some(issue);
            }
        }
    }

    rollup
}

fn pod_issue(pod: &PodResource) -> Option<String> {
    let status = pod.status.as_ref()?;
    let phase = status.phase.as_deref().unwrap_or("Unknown");

    if phase != "Running" && phase != "Succeeded" {
        return Some(format!("{} phase {}", pod_name(pod), phase.to_lowercase()));
    }

    for container in &status.container_statuses {
        if let Some(waiting) = container.state.as_ref().and_then(|state| state.waiting.as_ref()) {
            return Some(format!(
                "{} waiting: {}",
                pod_name(pod),
                waiting.reason.as_deref().unwrap_or("starting")
            ));
        }

        if let Some(terminated) = container
            .state
            .as_ref()
            .and_then(|state| state.terminated.as_ref())
        {
            return Some(format!(
                "{} terminated: {}",
                pod_name(pod),
                terminated.reason.as_deref().unwrap_or("terminated")
            ));
        }
    }

    if !status.container_statuses.is_empty() && !status.container_statuses.iter().all(|container| container.ready) {
        return Some(format!("{} containers not ready", pod_name(pod)));
    }

    None
}

fn incident_for_pod(pod: &PodResource) -> Option<(&'static str, String)> {
    let status = pod.status.as_ref()?;
    let phase = status.phase.as_deref().unwrap_or("Unknown");

    if is_terminal_pod(pod) {
        return None;
    }

    if matches!(phase, "Pending" | "Unknown" | "Failed") {
        return Some(("critical", format!("pod phase {}", phase.to_lowercase())));
    }

    for container in &status.container_statuses {
        if let Some(waiting) = container.state.as_ref().and_then(|state| state.waiting.as_ref()) {
            let severity = match waiting.reason.as_deref() {
                Some("CrashLoopBackOff" | "ImagePullBackOff" | "ErrImagePull") => "critical",
                _ => "warning",
            };
            return Some((
                severity,
                format!("waiting: {}", waiting.reason.as_deref().unwrap_or("starting")),
            ));
        }
    }

    let restart_count = pod_restart_count(pod);
    if restart_count > 0 {
        return Some((
            "warning",
            format!(
                "{} restart{} recorded",
                restart_count,
                if restart_count == 1 { "" } else { "s" }
            ),
        ));
    }

    if phase == "Running"
        && !status.container_statuses.is_empty()
        && !status.container_statuses.iter().all(|container| container.ready)
    {
        return Some(("warning", "containers not ready".to_string()));
    }

    if let Some(reason) = &status.reason {
        return Some(("warning", reason.clone()));
    }

    None
}

fn pod_name(pod: &PodResource) -> &str {
    pod.metadata.name.as_deref().unwrap_or("unknown-pod")
}

fn pod_phase(pod: &PodResource) -> &str {
    pod.status
        .as_ref()
        .and_then(|status| status.phase.as_deref())
        .unwrap_or("Unknown")
}

fn pod_restart_count(pod: &PodResource) -> i32 {
    pod.status
        .as_ref()
        .map(|status| {
            status
                .container_statuses
                .iter()
                .map(|container| container.restart_count)
                .sum::<i32>()
        })
        .unwrap_or(0)
}

fn is_terminal_pod(pod: &PodResource) -> bool {
    matches!(pod_phase(pod), "Succeeded" | "Failed")
}

fn incident_rank(severity: &str) -> u8 {
    match severity {
        "critical" => 0,
        "warning" => 1,
        _ => 2,
    }
}

fn is_node_ready(node: &NodeResource) -> bool {
    node.status
        .as_ref()
        .and_then(|status| {
            status
                .conditions
                .iter()
                .find(|condition| condition.type_name.as_deref() == Some("Ready"))
        })
        .and_then(|condition| condition.status.as_deref())
        == Some("True")
}

fn node_name(node: &NodeResource) -> &str {
    node.metadata.name.as_deref().unwrap_or("unknown-node")
}

fn unavailable_live_overview(reason: impl Into<String>) -> LiveOverview {
    LiveOverview {
        available: false,
        stale: false,
        source: "snapshot-only",
        refreshed_at_epoch: unix_epoch_seconds(),
        refresh_interval_seconds: LIVE_REFRESH_INTERVAL_SECONDS,
        summary: LiveSummary {
            critical_services: service_targets().len(),
            affected_namespaces: tracked_namespaces().len(),
            ..LiveSummary::default()
        },
        services: Vec::new(),
        incidents: Vec::new(),
        error: Some(reason.into()),
    }
}

fn unix_epoch_seconds() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

fn json_error(status: StatusCode, message: &str, detail: &str) -> Response {
    (status, Json(json!({ "error": message, "detail": detail }))).into_response()
}
