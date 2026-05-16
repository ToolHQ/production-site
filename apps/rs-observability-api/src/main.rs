use std::{
    collections::{BTreeMap, BTreeSet},
    env,
    net::SocketAddr,
    path::{Component, Path, PathBuf},
    sync::Arc,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use reqwest::{
    header::{HeaderMap, HeaderValue as ReqwestHeaderValue, ACCEPT, AUTHORIZATION},
    Certificate, Client,
};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::sync::RwLock;

mod app;

const INDEX_HTML: &str = include_str!("../web-v2/dist/index.html");
const ASSET_JS: &[u8] = include_bytes!("../web-v2/dist/assets/app.js");
const ASSET_CSS: &[u8] = include_bytes!("../web-v2/dist/assets/app.css");
const FAVICON_SVG: &[u8] = include_bytes!("../web-v2/dist/favicon.svg");

const LIVE_CACHE_TTL: Duration = Duration::from_secs(10);
const LIVE_REFRESH_INTERVAL_SECONDS: u64 = 15;
const PROMETHEUS_CACHE_TTL: Duration = Duration::from_secs(45);
const PROMETHEUS_REFRESH_INTERVAL_SECONDS: u64 = 60;
const PROMETHEUS_WINDOW_MINUTES: u64 = 60;
const PROMETHEUS_STEP_SECONDS: u64 = 300;
const PROMETHEUS_BASE_URL_DEFAULT: &str =
    "http://coroot-prometheus-server.coroot.svc.cluster.local";

const KNOWN_REPORTS: &[(&str, &str, &str, &str)] = &[
    (
        "catalog-json",
        "Catalog JSON",
        "latest-catalog/catalog.json",
        "json",
    ),
    (
        "catalog-html",
        "Catalog HTML",
        "latest-catalog/catalog.html",
        "html",
    ),
    (
        "catalog-md",
        "Catalog Markdown",
        "latest-catalog/catalog.md",
        "markdown",
    ),
    (
        "inventory-html",
        "Inventory HTML",
        "latest/inventory.html",
        "html",
    ),
    (
        "inventory-md",
        "Inventory Markdown",
        "latest/inventory.md",
        "markdown",
    ),
];

#[derive(Clone)]
struct AppState {
    reports_root: Arc<PathBuf>,
    live_monitor: Option<Arc<LiveMonitor>>,
    prometheus_monitor: Arc<PrometheusMonitor>,
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

#[derive(Clone)]
struct PrometheusMonitor {
    client: Client,
    base_url: String,
    cache: Arc<RwLock<Option<CachedMetricsOverview>>>,
}

#[derive(Clone)]
struct CachedMetricsOverview {
    fetched_at: Instant,
    service_signature: String,
    payload: MetricsOverview,
}

#[derive(Serialize)]
struct HealthResponse {
    status: &'static str,
    service: &'static str,
    live_cluster_api: bool,
    prometheus_metrics_api: bool,
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
    nodes: Vec<NodeStat>,
    services: Vec<LiveService>,
    incidents: Vec<LiveIncident>,
    metrics: MetricsOverview,
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
    #[serde(skip_serializing)]
    pod_names: Vec<String>,
}

#[derive(Serialize, Clone)]
struct LiveIncident {
    severity: &'static str,
    namespace: String,
    resource: String,
    message: String,
}

#[derive(Serialize, Clone)]
struct MetricsOverview {
    available: bool,
    stale: bool,
    source: &'static str,
    refreshed_at_epoch: u64,
    refresh_interval_seconds: u64,
    window_minutes: u64,
    cluster: ClusterTimeseries,
    services: Vec<ServiceTimeseries>,
    top_restarts: Vec<RestartHotspot>,
    error: Option<String>,
}

#[derive(Serialize, Clone, Default)]
struct ClusterTimeseries {
    cpu_percent_latest: f64,
    cpu_cores_used_latest: f64,
    memory_percent_latest: f64,
    memory_bytes_used_latest: f64,
    restart_events_last_hour: f64,
    cpu_percent_series: Vec<MetricPoint>,
    memory_percent_series: Vec<MetricPoint>,
    restart_pressure_series: Vec<MetricPoint>,
}

#[derive(Serialize, Clone)]
struct ServiceTimeseries {
    id: &'static str,
    label: &'static str,
    cpu_cores_latest: f64,
    memory_bytes_latest: f64,
    cpu_series: Vec<MetricPoint>,
    memory_series: Vec<MetricPoint>,
}

#[derive(Serialize, Clone)]
struct RestartHotspot {
    namespace: String,
    pod: String,
    restarts_last_hour: f64,
}

#[derive(Serialize, Clone)]
struct MetricPoint {
    ts: u64,
    value: f64,
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
    allocatable: Option<NodeAllocatable>,
}

#[derive(Deserialize, Clone, Default)]
struct NodeAllocatable {
    cpu: Option<String>,
    memory: Option<String>,
    #[serde(rename = "ephemeral-storage")]
    ephemeral_storage: Option<String>,
}

#[derive(Deserialize, Clone, Default)]
struct NodeCondition {
    #[serde(rename = "type")]
    type_name: Option<String>,
    status: Option<String>,
}

#[derive(Serialize, Clone)]
struct NodeStat {
    name: String,
    role: String,
    ready: bool,
    disk_pressure: bool,
    memory_pressure: bool,
    cpu_millicores: u64,
    memory_bytes: u64,
    ephemeral_storage_bytes: u64,
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

#[derive(Deserialize, Clone, Default)]
struct PrometheusResponse<T> {
    data: T,
}

#[derive(Deserialize, Clone, Default)]
struct PrometheusQueryData {
    #[serde(default)]
    result: Vec<PrometheusSeries>,
}

#[derive(Deserialize, Clone, Default)]
struct PrometheusSeries {
    #[serde(default)]
    metric: BTreeMap<String, String>,
    value: Option<(f64, String)>,
    #[serde(default)]
    values: Vec<(f64, String)>,
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
    let prometheus_monitor = Arc::new(PrometheusMonitor::new());

    let state = AppState {
        reports_root: Arc::new(reports_root),
        live_monitor,
        prometheus_monitor,
    };

    let app = app::build_app(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    println!("rs-observability-api listening on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("bind listener");
    axum::serve(listener, app).await.expect("serve axum app");
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
        matches!(
            component,
            Component::ParentDir | Component::RootDir | Component::Prefix(_)
        )
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
        let token =
            tokio::fs::read_to_string("/var/run/secrets/kubernetes.io/serviceaccount/token")
                .await
                .map_err(|error| format!("read service account token: {}", error))?;
        let cluster_ca = tokio::fs::read("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
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
        let node_stats = build_node_stats(&nodes.items);

        Ok(LiveOverview {
            available: true,
            stale: false,
            source: "in-cluster-api",
            refreshed_at_epoch: unix_epoch_seconds(),
            refresh_interval_seconds: LIVE_REFRESH_INTERVAL_SECONDS,
            summary,
            nodes: node_stats,
            services,
            incidents,
            metrics: unavailable_metrics_overview("metrics not fetched yet"),
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

impl PrometheusMonitor {
    fn new() -> Self {
        let client = Client::builder()
            .timeout(Duration::from_secs(8))
            .build()
            .unwrap_or_else(|error| panic!("build Prometheus client: {}", error));

        Self {
            client,
            base_url: env::var("PROMETHEUS_BASE_URL")
                .unwrap_or_else(|_| PROMETHEUS_BASE_URL_DEFAULT.to_string()),
            cache: Arc::new(RwLock::new(None)),
        }
    }

    async fn cached_or_refresh(&self, services: &[LiveService]) -> MetricsOverview {
        let signature = service_signature(services);
        if let Some(payload) = self.fresh_cache(&signature).await {
            return payload;
        }

        match self.fetch_metrics(services).await {
            Ok(payload) => {
                *self.cache.write().await = Some(CachedMetricsOverview {
                    fetched_at: Instant::now(),
                    service_signature: signature,
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
                    unavailable_metrics_overview(error)
                }
            }
        }
    }

    async fn fresh_cache(&self, signature: &str) -> Option<MetricsOverview> {
        let guard = self.cache.read().await;
        guard.as_ref().and_then(|entry| {
            if entry.service_signature == signature
                && entry.fetched_at.elapsed() < PROMETHEUS_CACHE_TTL
            {
                Some(entry.payload.clone())
            } else {
                None
            }
        })
    }

    async fn cached_payload(&self) -> Option<MetricsOverview> {
        let guard = self.cache.read().await;
        guard.as_ref().map(|entry| entry.payload.clone())
    }

    async fn fetch_metrics(&self, services: &[LiveService]) -> Result<MetricsOverview, String> {
        let end = unix_epoch_seconds();
        let start = end.saturating_sub(PROMETHEUS_WINDOW_MINUTES * 60);
        let namespace_regex = tracked_namespace_regex();

        let cluster_cpu_percent_query = r#"100 * sum(rate(node_resources_cpu_usage_seconds_total[5m])) / sum(node_resources_cpu_logical_cores)"#;
        let cluster_cpu_used_query = r#"sum(rate(node_resources_cpu_usage_seconds_total[5m]))"#;
        let cluster_memory_percent_query = r#"100 * (sum(node_resources_memory_total_bytes) - sum(node_resources_memory_available_bytes)) / sum(node_resources_memory_total_bytes)"#;
        let cluster_memory_used_query = r#"sum(node_resources_memory_total_bytes) - sum(node_resources_memory_available_bytes)"#;
        let restart_pressure_query = format!(
            r#"sum(increase(kube_pod_container_status_restarts_total{{namespace=~"{}"}}[15m]))"#,
            namespace_regex
        );
        let restart_last_hour_query = format!(
            r#"sum(increase(kube_pod_container_status_restarts_total{{namespace=~"{}"}}[1h]))"#,
            namespace_regex
        );
        let pod_cpu_query = format!(
            r#"sum by (container_id,app_id) (rate(container_resources_cpu_usage_seconds_total{{container_id=~"/k8s/({})/.+"}}[5m]))"#,
            namespace_regex
        );
        let pod_memory_query = format!(
            r#"sum by (container_id,app_id) (container_resources_memory_rss_bytes{{container_id=~"/k8s/({})/.+"}})"#,
            namespace_regex
        );
        let top_restart_query = format!(
            r#"topk(8, sum by (namespace,pod) (increase(kube_pod_container_status_restarts_total{{namespace=~"{}"}}[1h])))"#,
            namespace_regex
        );

        let cluster_cpu_percent_series = self
            .query_range_points(
                cluster_cpu_percent_query,
                start,
                end,
                PROMETHEUS_STEP_SECONDS,
            )
            .await?;
        let cluster_cpu_used_series = self
            .query_range_points(cluster_cpu_used_query, start, end, PROMETHEUS_STEP_SECONDS)
            .await?;
        let cluster_memory_percent_series = self
            .query_range_points(
                cluster_memory_percent_query,
                start,
                end,
                PROMETHEUS_STEP_SECONDS,
            )
            .await?;
        let cluster_memory_used_series = self
            .query_range_points(
                cluster_memory_used_query,
                start,
                end,
                PROMETHEUS_STEP_SECONDS,
            )
            .await?;
        let restart_pressure_series = self
            .query_range_points(&restart_pressure_query, start, end, PROMETHEUS_STEP_SECONDS)
            .await?;
        let restart_events_last_hour = self.query_instant_value(&restart_last_hour_query).await?;
        let top_restarts = self.query_restart_hotspots(&top_restart_query).await?;
        let pod_cpu_series = self
            .query_range_series(&pod_cpu_query, start, end, PROMETHEUS_STEP_SECONDS)
            .await?;
        let pod_memory_series = self
            .query_range_series(&pod_memory_query, start, end, PROMETHEUS_STEP_SECONDS)
            .await?;

        let service_metrics = services
            .iter()
            .map(|service| build_service_timeseries(service, &pod_cpu_series, &pod_memory_series))
            .collect();

        Ok(MetricsOverview {
            available: true,
            stale: false,
            source: "coroot-prometheus",
            refreshed_at_epoch: unix_epoch_seconds(),
            refresh_interval_seconds: PROMETHEUS_REFRESH_INTERVAL_SECONDS,
            window_minutes: PROMETHEUS_WINDOW_MINUTES,
            cluster: ClusterTimeseries {
                cpu_percent_latest: latest_point_value(&cluster_cpu_percent_series),
                cpu_cores_used_latest: latest_point_value(&cluster_cpu_used_series),
                memory_percent_latest: latest_point_value(&cluster_memory_percent_series),
                memory_bytes_used_latest: latest_point_value(&cluster_memory_used_series),
                restart_events_last_hour,
                cpu_percent_series: cluster_cpu_percent_series,
                memory_percent_series: cluster_memory_percent_series,
                restart_pressure_series,
            },
            services: service_metrics,
            top_restarts,
            error: None,
        })
    }

    async fn query_range_points(
        &self,
        query: &str,
        start: u64,
        end: u64,
        step: u64,
    ) -> Result<Vec<MetricPoint>, String> {
        let series = self.query_range_series(query, start, end, step).await?;
        Ok(series
            .into_iter()
            .next()
            .map(|entry| convert_values_to_points(&entry.values))
            .unwrap_or_default())
    }

    async fn query_range_series(
        &self,
        query: &str,
        start: u64,
        end: u64,
        step: u64,
    ) -> Result<Vec<PrometheusSeries>, String> {
        let url = format!("{}/api/v1/query_range", self.base_url);
        let response = self
            .client
            .get(url)
            .query(&[
                ("query", query.to_string()),
                ("start", start.to_string()),
                ("end", end.to_string()),
                ("step", step.to_string()),
            ])
            .send()
            .await
            .map_err(|error| format!("request Prometheus range query: {}", error))?;
        let payload = response
            .error_for_status()
            .map_err(|error| format!("Prometheus range status error: {}", error))?
            .json::<PrometheusResponse<PrometheusQueryData>>()
            .await
            .map_err(|error| format!("decode Prometheus range response: {}", error))?;

        Ok(payload.data.result)
    }

    async fn query_instant_value(&self, query: &str) -> Result<f64, String> {
        let series = self.query_instant_series(query).await?;
        Ok(series
            .into_iter()
            .next()
            .and_then(|entry| entry.value)
            .map(|(_, value)| parse_prometheus_value(&value))
            .unwrap_or(0.0))
    }

    async fn query_instant_series(&self, query: &str) -> Result<Vec<PrometheusSeries>, String> {
        let url = format!("{}/api/v1/query", self.base_url);
        let response = self
            .client
            .get(url)
            .query(&[("query", query.to_string())])
            .send()
            .await
            .map_err(|error| format!("request Prometheus instant query: {}", error))?;
        let payload = response
            .error_for_status()
            .map_err(|error| format!("Prometheus instant status error: {}", error))?
            .json::<PrometheusResponse<PrometheusQueryData>>()
            .await
            .map_err(|error| format!("decode Prometheus instant response: {}", error))?;

        Ok(payload.data.result)
    }

    async fn query_restart_hotspots(&self, query: &str) -> Result<Vec<RestartHotspot>, String> {
        let mut hotspots: Vec<RestartHotspot> = self
            .query_instant_series(query)
            .await?
            .into_iter()
            .filter_map(|series| {
                let (_, value) = series.value?;
                let restarts_last_hour = parse_prometheus_value(&value);
                if restarts_last_hour <= 0.0 {
                    return None;
                }

                Some(RestartHotspot {
                    namespace: series
                        .metric
                        .get("namespace")
                        .cloned()
                        .unwrap_or_else(|| "unknown".to_string()),
                    pod: series
                        .metric
                        .get("pod")
                        .cloned()
                        .unwrap_or_else(|| "unknown".to_string()),
                    restarts_last_hour,
                })
            })
            .collect();

        hotspots.sort_by(|left, right| {
            right
                .restarts_last_hour
                .partial_cmp(&left.restarts_last_hour)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        hotspots.truncate(8);
        Ok(hotspots)
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
                            .or_else(|| {
                                item.status
                                    .as_ref()
                                    .and_then(|status| status.ready_replicas)
                            })
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

    let mut status =
        if desired > 0 && ready >= desired && available >= desired && !rollup.has_blocker {
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
        pod_names: matching_pods
            .iter()
            .map(|pod| pod_name(pod).to_string())
            .collect(),
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
        pod_names: Vec::new(),
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

    for pod in pods
        .iter()
        .filter(|pod| namespaces.contains(pod.metadata.namespace.as_deref().unwrap_or_default()))
    {
        if let Some((severity, message)) = incident_for_pod(pod) {
            incidents.push(LiveIncident {
                severity,
                namespace: pod
                    .metadata
                    .namespace
                    .clone()
                    .unwrap_or_else(|| "unknown".to_string()),
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
        healthy_services: services
            .iter()
            .filter(|service| service.status == "healthy")
            .count(),
        degraded_services: services
            .iter()
            .filter(|service| service.status == "degraded")
            .count(),
        down_services: services
            .iter()
            .filter(|service| service.status == "down")
            .count(),
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

fn build_node_stats(nodes: &[NodeResource]) -> Vec<NodeStat> {
    let mut stats: Vec<NodeStat> = nodes
        .iter()
        .map(|node| {
            let name = node_name(node).to_string();
            let labels = &node.metadata.labels;
            let role = if labels
                .get("node-role.kubernetes.io/control-plane")
                .is_some()
            {
                "control-plane".to_string()
            } else {
                "worker".to_string()
            };

            let ready = is_node_ready(node);
            let disk_pressure = node_condition_true(node, "DiskPressure");
            let memory_pressure = node_condition_true(node, "MemoryPressure");

            let (cpu_millicores, memory_bytes, ephemeral_storage_bytes) = node
                .status
                .as_ref()
                .and_then(|s| s.allocatable.as_ref())
                .map(|a| {
                    (
                        parse_cpu_to_millicores(a.cpu.as_deref().unwrap_or("0")),
                        parse_memory_to_bytes(a.memory.as_deref().unwrap_or("0")),
                        parse_memory_to_bytes(a.ephemeral_storage.as_deref().unwrap_or("0")),
                    )
                })
                .unwrap_or((0, 0, 0));

            NodeStat {
                name,
                role,
                ready,
                disk_pressure,
                memory_pressure,
                cpu_millicores,
                memory_bytes,
                ephemeral_storage_bytes,
            }
        })
        .collect();

    stats.sort_by(|a, b| a.name.cmp(&b.name));
    stats
}

fn node_condition_true(node: &NodeResource, condition_type: &str) -> bool {
    node.status
        .as_ref()
        .and_then(|s| {
            s.conditions
                .iter()
                .find(|c| c.type_name.as_deref() == Some(condition_type))
        })
        .and_then(|c| c.status.as_deref())
        == Some("True")
}

/// Parseia strings de CPU do Kubernetes para millicores.
/// Exemplos: "940m" → 940, "2" → 2000, "1500m" → 1500
fn parse_cpu_to_millicores(s: &str) -> u64 {
    if let Some(val) = s.strip_suffix('m') {
        val.parse::<u64>().unwrap_or(0)
    } else {
        s.parse::<u64>().unwrap_or(0).saturating_mul(1000)
    }
}

/// Parseia strings de memória/storage do Kubernetes para bytes.
/// Exemplos: "5593Mi" → bytes, "6Gi" → bytes, "1024Ki" → bytes, "1000000" → bytes
fn parse_memory_to_bytes(s: &str) -> u64 {
    if let Some(val) = s.strip_suffix("Ki") {
        return val.parse::<u64>().unwrap_or(0).saturating_mul(1024);
    }
    if let Some(val) = s.strip_suffix("Mi") {
        return val.parse::<u64>().unwrap_or(0).saturating_mul(1024 * 1024);
    }
    if let Some(val) = s.strip_suffix("Gi") {
        return val
            .parse::<u64>()
            .unwrap_or(0)
            .saturating_mul(1024 * 1024 * 1024);
    }
    if let Some(val) = s.strip_suffix('k') {
        return val.parse::<u64>().unwrap_or(0).saturating_mul(1000);
    }
    if let Some(val) = s.strip_suffix('M') {
        return val.parse::<u64>().unwrap_or(0).saturating_mul(1_000_000);
    }
    if let Some(val) = s.strip_suffix('G') {
        return val
            .parse::<u64>()
            .unwrap_or(0)
            .saturating_mul(1_000_000_000);
    }
    s.parse::<u64>().unwrap_or(0)
}

fn tracked_namespaces() -> BTreeSet<&'static str> {
    service_targets()
        .into_iter()
        .map(|target| target.namespace)
        .collect()
}

fn tracked_namespace_regex() -> String {
    tracked_namespaces()
        .into_iter()
        .collect::<Vec<_>>()
        .join("|")
}

fn service_signature(services: &[LiveService]) -> String {
    let mut parts = services
        .iter()
        .map(|service| {
            let mut pod_names = service.pod_names.clone();
            pod_names.sort();
            format!("{}:{}", service.id, pod_names.join(","))
        })
        .collect::<Vec<_>>();
    parts.sort();
    parts.join(";")
}

fn build_service_timeseries(
    service: &LiveService,
    cpu_series: &[PrometheusSeries],
    memory_series: &[PrometheusSeries],
) -> ServiceTimeseries {
    let cpu_points = aggregate_series_for_service(service, cpu_series);
    let memory_points = aggregate_series_for_service(service, memory_series);

    ServiceTimeseries {
        id: service.id,
        label: service.label,
        cpu_cores_latest: latest_point_value(&cpu_points),
        memory_bytes_latest: latest_point_value(&memory_points),
        cpu_series: cpu_points,
        memory_series: memory_points,
    }
}

fn aggregate_series_for_service(
    service: &LiveService,
    series_set: &[PrometheusSeries],
) -> Vec<MetricPoint> {
    let pod_names = service
        .pod_names
        .iter()
        .map(String::as_str)
        .collect::<BTreeSet<_>>();
    let workload_app_id = format!("/k8s/{}/{}", service.namespace, service.workload_name);
    let mut points = BTreeMap::<u64, f64>::new();

    for series in series_set
        .iter()
        .filter(|series| metric_matches_service(service, series, &pod_names, &workload_app_id))
    {
        for (timestamp, value) in &series.values {
            let bucket = timestamp.round() as u64;
            let parsed = parse_prometheus_value(value);
            *points.entry(bucket).or_insert(0.0) += parsed;
        }
    }

    points
        .into_iter()
        .map(|(ts, value)| MetricPoint { ts, value })
        .collect()
}

fn metric_matches_service(
    service: &LiveService,
    series: &PrometheusSeries,
    pod_names: &BTreeSet<&str>,
    workload_app_id: &str,
) -> bool {
    if series.metric.get("namespace").map(String::as_str) == Some(service.namespace)
        && series
            .metric
            .get("pod")
            .map(|pod| pod_names.contains(pod.as_str()))
            .unwrap_or(false)
    {
        return true;
    }

    if series.metric.get("app_id").map(String::as_str) == Some(workload_app_id) {
        return true;
    }

    series
        .metric
        .get("container_id")
        .and_then(|container_id| container_identity(container_id))
        .map(|(namespace, pod)| namespace == service.namespace && pod_names.contains(pod))
        .unwrap_or(false)
}

fn container_identity(container_id: &str) -> Option<(&str, &str)> {
    let mut parts = container_id.split('/').filter(|part| !part.is_empty());
    if parts.next()? != "k8s" {
        return None;
    }

    let namespace = parts.next()?;
    let pod = parts.next()?;
    Some((namespace, pod))
}

fn convert_values_to_points(values: &[(f64, String)]) -> Vec<MetricPoint> {
    values
        .iter()
        .map(|(timestamp, value)| MetricPoint {
            ts: timestamp.round() as u64,
            value: parse_prometheus_value(value),
        })
        .collect()
}

fn latest_point_value(points: &[MetricPoint]) -> f64 {
    points.last().map(|point| point.value).unwrap_or(0.0)
}

fn parse_prometheus_value(value: &str) -> f64 {
    value.parse::<f64>().unwrap_or(0.0)
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

fn selector_matches(
    labels: &BTreeMap<String, String>,
    selector: &BTreeMap<String, String>,
) -> bool {
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
        if phase == "Running"
            && !container_statuses.is_empty()
            && container_statuses.iter().all(|status| status.ready)
        {
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
        if let Some(waiting) = container
            .state
            .as_ref()
            .and_then(|state| state.waiting.as_ref())
        {
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

    if !status.container_statuses.is_empty()
        && !status
            .container_statuses
            .iter()
            .all(|container| container.ready)
    {
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
        if let Some(waiting) = container
            .state
            .as_ref()
            .and_then(|state| state.waiting.as_ref())
        {
            let severity = match waiting.reason.as_deref() {
                Some("CrashLoopBackOff" | "ImagePullBackOff" | "ErrImagePull") => "critical",
                _ => "warning",
            };
            return Some((
                severity,
                format!(
                    "waiting: {}",
                    waiting.reason.as_deref().unwrap_or("starting")
                ),
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
        && !status
            .container_statuses
            .iter()
            .all(|container| container.ready)
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
        nodes: Vec::new(),
        services: Vec::new(),
        incidents: Vec::new(),
        metrics: unavailable_metrics_overview("prometheus metrics unavailable"),
        error: Some(reason.into()),
    }
}

fn unavailable_metrics_overview(reason: impl Into<String>) -> MetricsOverview {
    MetricsOverview {
        available: false,
        stale: false,
        source: "prometheus-unavailable",
        refreshed_at_epoch: unix_epoch_seconds(),
        refresh_interval_seconds: PROMETHEUS_REFRESH_INTERVAL_SECONDS,
        window_minutes: PROMETHEUS_WINDOW_MINUTES,
        cluster: ClusterTimeseries::default(),
        services: Vec::new(),
        top_restarts: Vec::new(),
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
