use std::{
    collections::{BTreeMap, BTreeSet, HashMap},
    env,
    net::SocketAddr,
    path::{Component, Path, PathBuf},
    sync::{Arc, OnceLock},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use base64::{engine::general_purpose::STANDARD as BASE64_STANDARD, Engine as _};
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

const EXTERNAL_NODES_JSON: &str = include_str!("../config/external_nodes.json");

fn external_node_specs() -> &'static [ExternalNodeSpec] {
    static SPECS: OnceLock<Vec<ExternalNodeSpec>> = OnceLock::new();
    SPECS
        .get_or_init(|| {
            serde_json::from_str(EXTERNAL_NODES_JSON)
                .unwrap_or_else(|err| panic!("failed to parse external_nodes.json: {err}"))
        })
        .as_slice()
}

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
    secondary_live_monitor: Option<Arc<LiveMonitor>>,
    prometheus_monitor: Arc<PrometheusMonitor>,
    coroot_client: Option<Arc<CorootClient>>,
    clickhouse_client: Option<ClickHouseClient>,
    fleet_copilot: Option<Arc<fleet_copilot::FleetCopilotState>>,
}

#[derive(Clone)]
struct ClickHouseClient {
    http: Client,
    base_url: String,
}

#[derive(Deserialize, Default)]
struct ChFail2BanStatRow {
    total: String,
    failed: String,
    banned: String,
}

#[derive(Deserialize, Default, Clone)]
struct ChHoneypotStatRow {
    total: String,
    last24h: String,
    classified: String,
    unclassified: String,
}

#[derive(Deserialize, Default, Clone)]
struct ChHoneypotTagRow {
    tag: String,
    count: String,
}

#[derive(Deserialize, Clone)]
struct ChBannedIpRow {
    ip: String,
    hits: serde_json::Value,
    first_seen: serde_json::Value,
    last_seen: serde_json::Value,
    statuses: Vec<String>,
}

#[derive(Serialize, Clone, Default, Deserialize)]
pub(crate) struct BannedIpDetail {
    pub ip: String,
    pub hits: u64,
    pub first_seen: u64,
    pub last_seen: u64,
    pub statuses: Vec<String>,
}

#[derive(Deserialize, Default)]
struct ChResponse<T> {
    data: Vec<T>,
}

impl ClickHouseClient {
    fn new(base_url: String) -> Self {
        let http = Client::builder()
            .timeout(Duration::from_secs(8))
            .build()
            .expect("clickhouse http client");
        ClickHouseClient { http, base_url }
    }

    async fn fetch_fail2ban_stats(&self) -> Option<Fail2BanStats> {
        let query = "SELECT \
            count() as total, \
            countIf(status IN ('failed', 'found')) as failed, \
            countIf(status IN ('banned', 'ban')) as banned \
            FROM threat_intel_events \
            WHERE service IN ('fail2ban', 'sshd') AND timestamp >= now() - INTERVAL 7 DAY FORMAT JSON";

        let stats_resp = match self
            .http
            .get(&self.base_url)
            .query(&[("query", query)])
            .header("X-ClickHouse-User", "default")
            .header("X-ClickHouse-Key", "i4FtSOCFXu")
            .send()
            .await
        {
            Ok(resp) => resp,
            Err(e) => {
                eprintln!("ClickHouse fetch_fail2ban_stats error: {}", e);
                return None;
            }
        };

        if !stats_resp.status().is_success() {
            eprintln!(
                "ClickHouse fetch_fail2ban_stats failed: HTTP {}",
                stats_resp.status()
            );
            return None;
        }

        let stats_data = stats_resp
            .json::<ChResponse<ChFail2BanStatRow>>()
            .await
            .ok()?;
        let stat_row = stats_data.data.first()?;

        let ips_query = "SELECT ip, count() as hits, toUnixTimestamp(min(timestamp)) as first_seen, toUnixTimestamp(max(timestamp)) as last_seen, groupArray(status) as statuses \
            FROM threat_intel_events \
            WHERE service IN ('fail2ban', 'sshd') AND status IN ('banned', 'ban') AND timestamp >= now() - INTERVAL 7 DAY \
            GROUP BY ip ORDER BY hits DESC LIMIT 20 FORMAT JSON";

        let ips_resp = self
            .http
            .get(&self.base_url)
            .query(&[("query", ips_query)])
            .header("X-ClickHouse-User", "default")
            .header("X-ClickHouse-Key", "i4FtSOCFXu")
            .send()
            .await
            .ok()?;
        let ips_data = ips_resp.json::<ChResponse<ChBannedIpRow>>().await.ok()?;

        Some(Fail2BanStats {
            total: stat_row.total.parse().unwrap_or(0),
            failed: stat_row.failed.parse().unwrap_or(0),
            banned: stat_row.banned.parse().unwrap_or(0),
            banned_ip_details: ips_data
                .data
                .into_iter()
                .map(|r| BannedIpDetail {
                    ip: r.ip,
                    hits: r
                        .hits
                        .as_u64()
                        .unwrap_or_else(|| r.hits.as_str().unwrap_or("0").parse().unwrap_or(0)),
                    first_seen: r.first_seen.as_u64().unwrap_or_else(|| {
                        r.first_seen.as_str().unwrap_or("0").parse().unwrap_or(0)
                    }),
                    last_seen: r.last_seen.as_u64().unwrap_or_else(|| {
                        r.last_seen.as_str().unwrap_or("0").parse().unwrap_or(0)
                    }),
                    statuses: r.statuses,
                })
                .collect(),
            timestamp: unix_epoch_seconds(),
        })
    }

    pub(crate) async fn fetch_honeypot_overview(&self) -> HoneypotOverview {
        let stats_query = "SELECT count() as total, countIf(timestamp >= now() - INTERVAL 1 DAY) as last24h, countIf(classification != 'unknown') as classified, countIf(classification == 'unknown') as unclassified FROM threat_intel_events WHERE service = 'honeypot' FORMAT JSON";
        
        let stats_resp = match self.http.get(&self.base_url).query(&[("query", stats_query)]).header("X-ClickHouse-User", "default").header("X-ClickHouse-Key", "i4FtSOCFXu").send().await {
            Ok(resp) => resp,
            Err(_) => return HoneypotOverview::default(),
        };
        
        let stats_data = stats_resp.json::<ChResponse<ChHoneypotStatRow>>().await.unwrap_or_default();
        let stat_row = stats_data.data.first().cloned().unwrap_or_default();
        
        let top_tags_query = "SELECT classification as tag, count() as count FROM threat_intel_events WHERE service = 'honeypot' AND classification != 'unknown' GROUP BY tag ORDER BY count DESC LIMIT 10 FORMAT JSON";
        let tags_resp = self.http.get(&self.base_url).query(&[("query", top_tags_query)]).header("X-ClickHouse-User", "default").header("X-ClickHouse-Key", "i4FtSOCFXu").send().await.ok();
        let top_tags = if let Some(resp) = tags_resp {
            let tags_data = resp.json::<ChResponse<ChHoneypotTagRow>>().await.unwrap_or_default();
            tags_data.data.into_iter().map(|r| HoneypotTagCount { tag: r.tag, count: r.count.parse().unwrap_or(0) }).collect()
        } else {
            vec![]
        };

        let recent_query = "SELECT timestamp, method, path, ip, user_agent as userAgent, classification as tag FROM threat_intel_events WHERE service = 'honeypot' ORDER BY timestamp DESC LIMIT 15 FORMAT JSON";
        let recent_resp = self.http.get(&self.base_url).query(&[("query", recent_query)]).header("X-ClickHouse-User", "default").header("X-ClickHouse-Key", "i4FtSOCFXu").send().await.ok();
        let recent_requests = if let Some(resp) = recent_resp {
            let recent_data = resp.json::<ChResponse<HoneypotRecentRequest>>().await.unwrap_or_default();
            recent_data.data
        } else {
            vec![]
        };

        let mut node = HoneypotNodeStats::default();
        node.id = "AWS-EC2".to_string();
        node.cluster = "AWS-EC2".to_string();
        node.instance_host = "ec2.dnor.io".to_string();
        node.available = true;
        node.total = stat_row.total.parse().unwrap_or(0);
        node.last24h = stat_row.last24h.parse().unwrap_or(0);
        node.classified = stat_row.classified.parse().unwrap_or(0);
        node.unclassified = stat_row.unclassified.parse().unwrap_or(0);
        node.top_tags = top_tags;
        node.recent_requests = recent_requests;
        node.refreshed_at_epoch = unix_epoch_seconds();

        HoneypotOverview {
            available: true,
            nodes: vec![node],
        }
    }

    pub(crate) async fn fetch_honeypot_requests(&self, query: &HoneypotRequestsQuery) -> HoneypotRequestsResponse {
        let mut filters = vec!["service = 'honeypot'".to_string()];
        
        if let Some(m) = &query.method {
            filters.push(format!("method = '{}'", m.replace('\'', "''")));
        }
        if let Some(p) = &query.path {
            filters.push(format!("path ILIKE '%{}%'", p.replace('\'', "''")));
        }
        if let Some(ip) = &query.ip {
            filters.push(format!("ip = '{}'", ip.replace('\'', "''")));
        }
        if let Some(c) = &query.classification {
            filters.push(format!("classification = '{}'", c.replace('\'', "''")));
        }
        if query.exclude_internal.unwrap_or(false) {
            filters.push("path NOT ILIKE '/internal/%'".to_string());
        }
        
        let where_clause = filters.join(" AND ");
        
        let count_query = format!("SELECT count() as total FROM threat_intel_events WHERE {} FORMAT JSON", where_clause);
        let count_resp = self.http.get(&self.base_url).query(&[("query", &count_query)]).header("X-ClickHouse-User", "default").header("X-ClickHouse-Key", "i4FtSOCFXu").send().await.ok();
        let total = if let Some(resp) = count_resp {
            let data = resp.json::<ChResponse<ChFail2BanStatRow>>().await.unwrap_or_default();
            data.data.first().map(|r| r.total.parse().unwrap_or(0)).unwrap_or(0)
        } else {
            0
        };
        
        let limit = query.limit.unwrap_or(50).clamp(1, 100);
        let offset = query.offset.unwrap_or(0);
        
        let rows_query = format!("SELECT toUnixTimestamp(timestamp) as id, timestamp, method, path, toUInt16OrZero(status) as statusCode, ip as remoteIp, ip as remoteHostname, country, classification, time_elapsed as timeElapsed, user_agent as userAgent FROM threat_intel_events WHERE {} ORDER BY timestamp DESC LIMIT {} OFFSET {} FORMAT JSON", where_clause, limit, offset);
        
        let rows_resp = self.http.get(&self.base_url).query(&[("query", &rows_query)]).header("X-ClickHouse-User", "default").header("X-ClickHouse-Key", "i4FtSOCFXu").send().await.ok();
        let rows = if let Some(resp) = rows_resp {
            let data = resp.json::<ChResponse<HoneypotRequest>>().await.unwrap_or_default();
            data.data
        } else {
            vec![]
        };
        
        HoneypotRequestsResponse { total, rows }
    }
}

async fn build_coroot_client() -> Option<CorootClient> {
    let base_url = env::var("COROOT_BASE_URL")
        .unwrap_or_else(|_| "http://coroot.coroot.svc.cluster.local:8080".to_string());
    let project_id = env::var("COROOT_PROJECT_ID").unwrap_or_else(|_| "p3m78dle".to_string());
    match (env::var("COROOT_EMAIL"), env::var("COROOT_PASSWORD")) {
        (Ok(email), Ok(password)) => Some(CorootClient::new(base_url, email, password, project_id)),
        _ => {
            eprintln!("[warn] COROOT_EMAIL/COROOT_PASSWORD not set — coroot alerts disabled");
            None
        }
    }
}

impl AppState {
    /// T-332: inventário de hosts para o Fleet Copilot (OCI live + registry externo).
    pub(crate) async fn build_fleet_manifest(&self) -> Value {
        let mut hosts: Vec<Value> = Vec::new();

        for spec in external_node_specs() {
            let id = if spec.id.is_empty() {
                spec.fallback_name.clone()
            } else {
                spec.id.clone()
            };
            hosts.push(json!({
                "id": id,
                "name": spec.fallback_name,
                "cluster": spec.cluster,
                "role": spec.role,
                "ip": spec.instance_host,
                "source": "external_registry",
                "ops_via_gateway": spec.cluster == "SSD-NODES",
            }));
        }

        let mut oci_live = json!(null);
        if let Some(lm) = &self.live_monitor {
            let live = lm.cached_or_refresh().await;
            if live.available {
                for node in &live.nodes {
                    hosts.push(json!({
                        "name": node.name,
                        "cluster": node.cluster,
                        "role": node.role,
                        "ip": node.ip,
                        "ready": node.ready,
                        "source": "oci_kubernetes_live_overview",
                    }));
                }
                oci_live = json!({
                    "available": live.available,
                    "stale": live.stale,
                    "refreshed_at_epoch": live.refreshed_at_epoch,
                    "node_count": live.nodes.len(),
                });
            }
        }

        json!({
            "scope": {
                "description_pt": "Assistente read-only: comandos ops (disco/memória/k8s) rodam no gateway em SSDNodes; visão live dos nós OCI-K8s vem do Cluster Pulse; hosts externos no registry.",
                "gateway_host_id": "ssdnodes-6a12f10c9ef11",
                "data_sources": [
                    "fleet-ops-gateway (SSDNodes)",
                    "api/live/overview (OCI-K8s)",
                    "external_nodes.json"
                ],
            },
            "hosts": hosts,
            "oci_live": oci_live,
        })
    }

    /// T-333: anexa métricas live de nós mencionados (OCI + externos, max 3).
    pub(crate) async fn enrich_manifest_for_message(
        &self,
        mut manifest: Value,
        message: &str,
    ) -> Value {
        let needle = message.to_lowercase();
        let metrics = self.prometheus_monitor.fetch_node_metrics().await;

        if is_fleet_wide_resources_message(message) {
            let mut snapshot: Vec<Value> = Vec::new();
            if let Some(lm) = &self.live_monitor {
                let live = lm.cached_or_refresh().await;
                if live.available {
                    for node in &live.nodes {
                        let m = metrics.get(&node.name).cloned().unwrap_or_default();
                        snapshot.push(json!({
                            "name": node.name,
                            "cluster": node.cluster,
                            "metrics": m,
                        }));
                    }
                }
            }
            for spec in external_node_specs() {
                let id = if spec.id.is_empty() {
                    spec.fallback_name.clone()
                } else {
                    spec.id.clone()
                };
                let m = metrics
                    .get(&spec.fallback_name)
                    .or_else(|| metrics.get(&spec.instance_host))
                    .or_else(|| spec.endpoint_ip.as_ref().and_then(|ip| metrics.get(ip)))
                    .cloned()
                    .unwrap_or_default();
                snapshot.push(json!({
                    "id": id,
                    "name": spec.fallback_name,
                    "cluster": spec.cluster,
                    "metrics": m,
                }));
            }
            if let Some(obj) = manifest.as_object_mut() {
                obj.insert("fleet_metrics_snapshot".into(), json!(snapshot));
            }
        }

        let compare = is_compare_message(message);
        let matched_ids = match_manifest_host_ids(&needle, &manifest, compare);
        if matched_ids.is_empty() {
            return manifest;
        }

        let mut targeted_oci = Vec::new();
        let mut targeted_external = Vec::new();

        if let Some(lm) = &self.live_monitor {
            let live = lm.cached_or_refresh().await;
            if live.available {
                for node in &live.nodes {
                    if !matched_ids.iter().any(|id| id == &node.name) {
                        continue;
                    }
                    let m = metrics.get(&node.name).cloned().unwrap_or_default();
                    targeted_oci.push(json!({
                        "name": node.name,
                        "cluster": node.cluster,
                        "role": node.role,
                        "ip": node.ip,
                        "ready": node.ready,
                        "disk_pressure": node.disk_pressure,
                        "memory_pressure": node.memory_pressure,
                        "metrics": m,
                    }));
                }
            }
        }

        for spec in external_node_specs() {
            let id = if spec.id.is_empty() {
                spec.fallback_name.clone()
            } else {
                spec.id.clone()
            };
            if !matched_ids
                .iter()
                .any(|m| m == &id || m == &spec.fallback_name)
            {
                continue;
            }
            let m = metrics
                .get(&spec.fallback_name)
                .or_else(|| metrics.get(&spec.instance_host))
                .or_else(|| spec.endpoint_ip.as_ref().and_then(|ip| metrics.get(ip)))
                .cloned()
                .unwrap_or_default();
            targeted_external.push(json!({
                "id": id,
                "name": spec.fallback_name,
                "cluster": spec.cluster,
                "role": spec.role,
                "ip": spec.instance_host,
                "metrics": m,
            }));
        }

        if targeted_oci.is_empty() && targeted_external.is_empty() {
            return manifest;
        }
        if let Some(obj) = manifest.as_object_mut() {
            if !targeted_oci.is_empty() {
                obj.insert("targeted_oci_nodes".into(), json!(targeted_oci));
            }
            if !targeted_external.is_empty() {
                obj.insert("targeted_external_nodes".into(), json!(targeted_external));
            }
        }
        manifest
    }
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

#[derive(Serialize, Clone, Deserialize)]
struct CorootAlert {
    id: String,
    #[serde(default)]
    rule_id: String,
    #[serde(default)]
    rule_name: String,
    #[serde(default)]
    application_id: String,
    #[serde(default)]
    severity: String,
    #[serde(default)]
    summary: String,
    #[serde(default)]
    opened_at: u64,
    #[serde(default)]
    duration: u64,
    #[serde(default)]
    report: Option<String>,
}

#[derive(Serialize)]
pub(crate) struct CorootAlertsResponse {
    available: bool,
    alerts: Vec<CorootAlert>,
    total: u64,
    queried_at_epoch: u64,
    error: Option<String>,
}

#[derive(Serialize, Clone, Deserialize)]
struct CorootIncident {
    application_id: String,
    key: String,
    opened_at: u64,
    #[serde(default)]
    resolved_at: Option<u64>,
    severity: String,
    #[serde(default)]
    short_description: Option<String>,
    #[serde(default)]
    duration: u64,
}

#[derive(Serialize)]
pub(crate) struct CorootIncidentsResponse {
    available: bool,
    incidents: Vec<CorootIncident>,
    total: u64,
    queried_at_epoch: u64,
    error: Option<String>,
}

// --- Longhorn storage ---

#[derive(Serialize, Clone)]
pub(crate) struct LonghornVolume {
    name: String,
    pvc_name: String,
    namespace: String,
    state: String,
    robustness: String,
    replicas_desired: u32,
    size_bytes: u64,
    actual_size_bytes: u64,
    node: String,
}

#[derive(Serialize)]
pub(crate) struct LonghornResponse {
    available: bool,
    volumes: Vec<LonghornVolume>,
    total: usize,
    healthy: usize,
    degraded: usize,
    faulted: usize,
    queried_at_epoch: u64,
    error: Option<String>,
}

// K8s CRD deserialization helpers for Longhorn

#[derive(Deserialize, Clone, Default)]
struct LonghornVolumeResource {
    #[serde(default)]
    metadata: ObjectMeta,
    spec: Option<LonghornVolumeSpec>,
    status: Option<LonghornVolumeStatus>,
}

#[derive(Deserialize, Clone, Default)]
struct LonghornVolumeSpec {
    #[serde(default, rename = "numberOfReplicas")]
    number_of_replicas: u32,
    #[serde(default)]
    size: String,
}

#[derive(Deserialize, Clone, Default)]
struct LonghornVolumeStatus {
    #[serde(default)]
    state: String,
    #[serde(default)]
    robustness: String,
    #[serde(default, rename = "currentNodeID")]
    current_node_id: String,
    #[serde(default, rename = "actualSize")]
    actual_size: u64,
}

// --- Inventory: Workloads (Deployments, StatefulSets, DaemonSets) ---

#[derive(Serialize, Clone)]
pub(crate) struct WorkloadInfo {
    name: String,
    namespace: String,
    kind: String,
    replicas_desired: i32,
    replicas_ready: i32,
    replicas_available: i32,
    image: String,
    status: String, // "healthy" | "degraded" | "down"
}

#[derive(Serialize, Clone)]
pub(crate) struct WorkloadsResponse {
    available: bool,
    workloads: Vec<WorkloadInfo>,
    total: usize,
    healthy: usize,
    degraded: usize,
    down: usize,
    queried_at_epoch: u64,
    error: Option<String>,
}

// --- Inventory: Namespace Quotas ---

#[derive(Serialize, Clone)]
pub(crate) struct NamespaceQuota {
    name: String,
    cpu_request_used: String,
    cpu_request_limit: String,
    cpu_limit_used: String,
    cpu_limit_limit: String,
    mem_request_used: String,
    mem_request_limit: String,
    mem_limit_used: String,
    mem_limit_limit: String,
    pods_used: u32,
    pods_limit: u32,
    cpu_pressure_pct: f64,
    mem_pressure_pct: f64,
}

#[derive(Serialize, Clone)]
pub(crate) struct NamespacesResponse {
    available: bool,
    namespaces: Vec<NamespaceQuota>,
    total: usize,
    over_pressure: usize,
    queried_at_epoch: u64,
    error: Option<String>,
}

#[derive(Deserialize, Clone, Default)]
struct ResourceQuotaResource {
    #[serde(default)]
    metadata: ObjectMeta,
    status: Option<ResourceQuotaStatus>,
}

#[derive(Deserialize, Clone, Default)]
struct ResourceQuotaStatus {
    #[serde(default)]
    hard: BTreeMap<String, String>,
    #[serde(default)]
    used: BTreeMap<String, String>,
}

// --- Inventory: CronJobs ---

#[derive(Serialize, Clone)]
pub(crate) struct CronJobInfo {
    name: String,
    namespace: String,
    schedule: String,
    active: u32,
    last_run_at: Option<String>,
    last_run_succeeded: Option<bool>,
    last_schedule_time: Option<String>,
    suspended: bool,
}

#[derive(Serialize)]
pub(crate) struct CronJobsResponse {
    available: bool,
    cronjobs: Vec<CronJobInfo>,
    total: usize,
    healthy: usize,
    failed: usize,
    queried_at_epoch: u64,
    error: Option<String>,
}

// K8s CronJob/Job deserialization

#[derive(Deserialize, Clone, Default)]
struct CronJobResource {
    #[serde(default)]
    metadata: ObjectMeta,
    spec: Option<CronJobSpec>,
    status: Option<CronJobStatus>,
}

#[derive(Deserialize, Clone, Default)]
struct CronJobSpec {
    #[serde(default)]
    schedule: String,
    #[serde(default)]
    suspend: bool,
}

#[derive(Deserialize, Clone, Default)]
struct CronJobStatus {
    #[serde(default)]
    active: Vec<Value>,
    #[serde(default, rename = "lastScheduleTime")]
    last_schedule_time: Option<String>,
}

#[derive(Deserialize, Clone, Default)]
struct JobResource {
    #[serde(default)]
    metadata: ObjectMeta,
    status: Option<JobStatus>,
}

#[derive(Deserialize, Clone, Default)]
#[allow(dead_code)]
struct JobOwnerRef {
    name: String,
    #[serde(default)]
    kind: String,
}

#[derive(Deserialize, Clone, Default)]
struct JobStatus {
    #[serde(default)]
    succeeded: u32,
    #[serde(default)]
    failed: u32,
    #[serde(rename = "startTime")]
    start_time: Option<String>,
}

// --- Inventory: Ingresses ---

#[derive(Serialize, Clone)]
pub(crate) struct IngressInfo {
    name: String,
    namespace: String,
    hosts: Vec<String>,
    tls: bool,
    tls_secret: Option<String>,
    class: Option<String>,
}

#[derive(Serialize)]
pub(crate) struct IngressesResponse {
    available: bool,
    ingresses: Vec<IngressInfo>,
    total: usize,
    queried_at_epoch: u64,
    error: Option<String>,
}

#[derive(Deserialize, Clone, Default)]
struct IngressResource {
    #[serde(default)]
    metadata: ObjectMeta,
    spec: Option<IngressSpec>,
}

#[derive(Deserialize, Clone, Default)]
struct IngressSpec {
    #[serde(default, rename = "ingressClassName")]
    ingress_class_name: Option<String>,
    #[serde(default)]
    rules: Vec<IngressRule>,
    #[serde(default)]
    tls: Vec<IngressTls>,
}

#[derive(Deserialize, Clone, Default)]
struct IngressRule {
    host: Option<String>,
}

#[derive(Deserialize, Clone, Default)]
struct IngressTls {
    #[serde(default, rename = "secretName")]
    secret_name: Option<String>,
}

// --- Inventory: Certificates (cert-manager) ---

#[derive(Serialize, Clone)]
pub(crate) struct CertInfo {
    name: String,
    namespace: String,
    dns_names: Vec<String>,
    not_after: Option<String>,
    ready: bool,
    days_remaining: Option<i64>,
}

#[derive(Serialize)]
pub(crate) struct CertificatesResponse {
    available: bool,
    certificates: Vec<CertInfo>,
    total: usize,
    expiring_soon: usize,
    critical: usize,
    queried_at_epoch: u64,
    error: Option<String>,
}

#[derive(Deserialize, Clone, Default)]
struct CertResource {
    #[serde(default)]
    metadata: ObjectMeta,
    spec: Option<CertSpec>,
    status: Option<CertStatus>,
}

#[derive(Deserialize, Clone, Default)]
struct CertSpec {
    #[serde(default, rename = "dnsNames")]
    dns_names: Vec<String>,
}

#[derive(Deserialize, Clone, Default)]
struct CertStatus {
    #[serde(default, rename = "notAfter")]
    not_after: Option<String>,
    #[serde(default)]
    conditions: Vec<CertCondition>,
}

#[derive(Deserialize, Clone, Default)]
struct CertCondition {
    #[serde(rename = "type")]
    type_name: String,
    status: String,
}

// --- Coroot HTTP API client (internal) ---

#[derive(Deserialize)]
struct CorootApiResponse {
    data: CorootApiData,
}

#[derive(Deserialize)]
struct CorootApiData {
    alerts: Vec<CorootAlert>,
    #[allow(dead_code)]
    #[serde(default)]
    firing: u64,
}

#[derive(Deserialize)]
struct CorootIncidentsApiResponse {
    data: Vec<CorootIncident>,
}

#[derive(Clone)]
struct CorootClient {
    http: Client,
    base_url: String,
    email: String,
    password: String,
    project_id: String,
    session_cookie: Arc<RwLock<Option<String>>>,
}

fn filter_alerts(alerts: Vec<CorootAlert>) -> Vec<CorootAlert> {
    alerts
        .into_iter()
        .filter(|alert| {
            // 1. Filter out systemd timer/mount/transient false positives from host (Unknown) services
            let is_host_transient = alert.application_id.contains(":Unknown:")
                && (alert.rule_id == "instance-availability"
                    || alert.application_id.ends_with(".mount")
                    || alert.application_id.contains("systemd-")
                    || alert.application_id.contains("apt-")
                    || alert.application_id.contains("tmpfiles")
                    || alert.application_id.contains("gdrive")
                    || alert.application_id.contains("motd")
                    || alert.application_id.contains("man-db")
                    || alert.application_id.contains("packagekit")
                    || alert.application_id.contains("fstrim")
                    || alert.application_id.contains("e2scrub")
                    || alert.application_id.contains("esm-cache")
                    || alert.application_id.contains("update-notifier"));

            if is_host_transient {
                return false;
            }

            // 2. Filter out noisy Coroot-specific "new-log-patterns" warnings (which flag simple info/warning logs)
            if alert.rule_id == "new-log-patterns" && alert.severity == "warning" {
                return false;
            }

            // 3. Filter out noisy transient "kubernetes-events" warnings (like cronjobs, ImageGCFailed, transient scaling events)
            if alert.rule_id == "kubernetes-events" && alert.severity == "warning" {
                let is_transient_k8s_event = alert.summary.contains("UnexpectedJob")
                    || alert.summary.contains("ImageGCFailed")
                    || alert.summary.contains("FailedCreate")
                    || alert.summary.contains("FreeDiskSpaceFailed")
                    || alert.summary.contains("Update") // "Update" events are not failures
                    || alert.application_id.contains("CronJob")
                    || alert.application_id.is_empty()
                    || alert.application_id == ":::"
                    || alert.application_id.starts_with(":::");

                if is_transient_k8s_event {
                    return false;
                }
            }

            // 4. Filter out buggy Coroot "instance-restarts" warnings that indicate "restarted 0 times"
            if alert.rule_id == "instance-restarts" && alert.summary.contains("restarted 0 times") {
                return false;
            }

            // 5. Filter out host storage warnings for transient system directories if they are on /dev/sda1 and under 80% (which we cleared)
            if alert.rule_id == "storage-space"
                && alert.severity == "warning"
                && (alert.application_id.contains(":Unknown:")
                    || alert.summary.contains("containerd"))
            {
                return false;
            }

            true
        })
        .collect()
}

impl CorootClient {
    fn new(base_url: String, email: String, password: String, project_id: String) -> Self {
        let http = Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .expect("coroot http client");
        CorootClient {
            http,
            base_url,
            email,
            password,
            project_id,
            session_cookie: Arc::new(RwLock::new(None)),
        }
    }

    async fn login(&self) -> Result<String, String> {
        let url = format!("{}/api/login", self.base_url);
        let resp = self
            .http
            .post(&url)
            .json(&json!({"email": &self.email, "password": &self.password}))
            .send()
            .await
            .map_err(|e| format!("coroot login request failed: {}", e))?;

        if !resp.status().is_success() {
            return Err(format!("coroot login failed: HTTP {}", resp.status()));
        }

        // Extract the session cookie value from Set-Cookie header
        let cookie = resp
            .headers()
            .get("set-cookie")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| {
                // Format: "coroot_session=<value>; Path=..."
                s.split(';').next().map(|s| s.trim().to_string())
            })
            .ok_or_else(|| "coroot login: no session cookie in response".to_string())?;

        *self.session_cookie.write().await = Some(cookie.clone());
        Ok(cookie)
    }

    async fn do_fetch_alerts(&self, cookie: &str) -> Result<CorootApiData, String> {
        let url = format!(
            "{}/api/project/{}/alerts?limit=200",
            self.base_url, self.project_id
        );
        let resp = self
            .http
            .get(&url)
            .header("Cookie", cookie)
            .send()
            .await
            .map_err(|e| format!("coroot alerts request failed: {}", e))?;

        if resp.status().as_u16() == 401 {
            return Err("401".to_string());
        }
        if !resp.status().is_success() {
            return Err(format!("coroot alerts HTTP {}", resp.status()));
        }

        let api_resp: CorootApiResponse = resp.json().await.map_err(|e| {
            eprintln!("[coroot] alerts parse error: {}", e);
            format!("coroot alerts parse error: {}", e)
        })?;

        Ok(api_resp.data)
    }

    async fn do_fetch_incidents(&self, cookie: &str) -> Result<Vec<CorootIncident>, String> {
        let url = format!(
            "{}/api/project/{}/incidents?limit=20",
            self.base_url, self.project_id
        );
        let resp = self
            .http
            .get(&url)
            .header("Cookie", cookie)
            .send()
            .await
            .map_err(|e| format!("coroot incidents request failed: {}", e))?;

        if resp.status().as_u16() == 401 {
            return Err("401".to_string());
        }
        if !resp.status().is_success() {
            return Err(format!("coroot incidents HTTP {}", resp.status()));
        }

        let api_resp: CorootIncidentsApiResponse = resp.json().await.map_err(|e| {
            eprintln!("[coroot] incidents parse error: {}", e);
            format!("coroot incidents parse error: {}", e)
        })?;

        Ok(api_resp.data)
    }

    async fn fetch_incidents(&self) -> CorootIncidentsResponse {
        let now = unix_epoch_seconds();

        let cookie = {
            let lock = self.session_cookie.read().await;
            lock.clone()
        };

        let cookie = match cookie {
            Some(c) => c,
            None => match self.login().await {
                Ok(c) => c,
                Err(e) => {
                    return CorootIncidentsResponse {
                        available: false,
                        incidents: vec![],
                        total: 0,
                        queried_at_epoch: now,
                        error: Some(e),
                    }
                }
            },
        };

        match self.do_fetch_incidents(&cookie).await {
            Ok(incidents) => {
                let total = incidents.len() as u64;
                CorootIncidentsResponse {
                    available: true,
                    total,
                    incidents,
                    queried_at_epoch: now,
                    error: None,
                }
            }
            Err(e) if e == "401" => {
                *self.session_cookie.write().await = None;
                match self.login().await {
                    Ok(new_cookie) => match self.do_fetch_incidents(&new_cookie).await {
                        Ok(incidents) => {
                            let total = incidents.len() as u64;
                            CorootIncidentsResponse {
                                available: true,
                                total,
                                incidents,
                                queried_at_epoch: now,
                                error: None,
                            }
                        }
                        Err(e2) => CorootIncidentsResponse {
                            available: false,
                            incidents: vec![],
                            total: 0,
                            queried_at_epoch: now,
                            error: Some(e2),
                        },
                    },
                    Err(e2) => CorootIncidentsResponse {
                        available: false,
                        incidents: vec![],
                        total: 0,
                        queried_at_epoch: now,
                        error: Some(format!("re-login failed: {}", e2)),
                    },
                }
            }
            Err(e) => CorootIncidentsResponse {
                available: false,
                incidents: vec![],
                total: 0,
                queried_at_epoch: now,
                error: Some(e),
            },
        }
    }

    async fn fetch_alerts(&self) -> CorootAlertsResponse {
        let now = unix_epoch_seconds();

        let cookie = {
            let lock = self.session_cookie.read().await;
            lock.clone()
        };

        let cookie = match cookie {
            Some(c) => c,
            None => match self.login().await {
                Ok(c) => c,
                Err(e) => {
                    return CorootAlertsResponse {
                        available: false,
                        alerts: vec![],
                        total: 0,
                        queried_at_epoch: now,
                        error: Some(e),
                    }
                }
            },
        };

        match self.do_fetch_alerts(&cookie).await {
            Ok(data) => {
                let filtered = filter_alerts(data.alerts);
                let total = filtered.len() as u64;
                CorootAlertsResponse {
                    available: true,
                    total,
                    alerts: filtered,
                    queried_at_epoch: now,
                    error: None,
                }
            }
            Err(e) if e == "401" => {
                // Session expired — clear cookie and re-login
                *self.session_cookie.write().await = None;
                match self.login().await {
                    Ok(new_cookie) => match self.do_fetch_alerts(&new_cookie).await {
                        Ok(data) => {
                            let filtered = filter_alerts(data.alerts);
                            let total = filtered.len() as u64;
                            CorootAlertsResponse {
                                available: true,
                                total,
                                alerts: filtered,
                                queried_at_epoch: now,
                                error: None,
                            }
                        }
                        Err(e2) => CorootAlertsResponse {
                            available: false,
                            alerts: vec![],
                            total: 0,
                            queried_at_epoch: now,
                            error: Some(e2),
                        },
                    },
                    Err(e2) => CorootAlertsResponse {
                        available: false,
                        alerts: vec![],
                        total: 0,
                        queried_at_epoch: now,
                        error: Some(format!("re-login failed: {}", e2)),
                    },
                }
            }
            Err(e) => CorootAlertsResponse {
                available: false,
                alerts: vec![],
                total: 0,
                queried_at_epoch: now,
                error: Some(e),
            },
        }
    }
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
    /// Real host utilization per node (keyed by node name, e.g. "k8s-node-1").
    /// Only populated for nodes that have node_exporter running (workers via kubecost).
    #[serde(default)]
    node_metrics: HashMap<String, NodeMetrics>,
    services: Vec<LiveService>,
    incidents: Vec<LiveIncident>,
    metrics: MetricsOverview,
    #[serde(default)]
    honeypot: HoneypotOverview,
    error: Option<String>,
}

#[derive(Serialize, Clone, Default, Deserialize)]
struct HoneypotTagCount {
    tag: String,
    count: u64,
}

#[derive(Serialize, Clone, Default)]
struct HoneypotNodeStats {
    id: String,
    cluster: String,
    instance_host: String,
    available: bool,
    total: u64,
    last24h: u64,
    classified: u64,
    unclassified: u64,
    top_tags: Vec<HoneypotTagCount>,
    #[serde(default)]
    requests_24h: Vec<MetricPoint>,
    #[serde(default)]
    requests_7d: Vec<MetricPoint>,
    refreshed_at_epoch: u64,
    error: Option<String>,
}

#[derive(Serialize, Clone, Default)]
struct HoneypotOverview {
    available: bool,
    nodes: Vec<HoneypotNodeStats>,
}

#[derive(Deserialize, Default)]
struct QdbbackThreatTimeseries {
    #[serde(default, rename = "requests24h")]
    requests_24h: Vec<MetricPoint>,
    #[serde(default, rename = "requests7d")]
    requests_7d: Vec<MetricPoint>,
}

#[derive(Deserialize)]
struct QdbbackThreatSummary {
    total: u64,
    last24h: u64,
    classified: u64,
    unclassified: u64,
    #[serde(default, rename = "topTags")]
    top_tags: Vec<HoneypotTagCount>,
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
    /// Per-node historical time series (last 60m at 5m resolution) from Prometheus node_exporter.
    /// Keyed by K8s node name. Used to pre-seed sparklines in the frontend.
    node_history: HashMap<String, NodeTimeseries>,
    error: Option<String>,
}

/// Historical sparkline data for a single node (CPU%, mem%, disk%).
#[derive(Serialize, Clone, Default)]
struct NodeTimeseries {
    cpu_percent_series: Vec<MetricPoint>,
    mem_percent_series: Vec<MetricPoint>,
    disk_percent_series: Vec<MetricPoint>,
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

#[derive(Serialize, Deserialize, Clone, Default)]
struct MetricPoint {
    timestamp: u64,
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
    template: Option<PodTemplateSpec>,
}

#[derive(Deserialize, Clone, Default)]
struct PodTemplateSpec {
    spec: Option<PodTemplateContainerSpec>,
}

#[derive(Deserialize, Clone, Default)]
struct PodTemplateContainerSpec {
    #[serde(default)]
    containers: Vec<ContainerSpec>,
}

#[derive(Deserialize, Clone, Default)]
struct ContainerSpec {
    #[serde(default)]
    image: String,
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
    template: Option<PodTemplateSpec>,
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
    #[serde(default)]
    addresses: Vec<NodeAddress>,
    #[serde(rename = "nodeInfo")]
    node_info: Option<NodeSystemInfo>,
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

#[derive(Deserialize, Clone, Default)]
struct NodeAddress {
    #[serde(rename = "type")]
    type_name: Option<String>,
    address: Option<String>,
}

#[derive(Deserialize, Clone, Default)]
struct NodeSystemInfo {
    #[serde(default)]
    architecture: String,
    #[serde(default, rename = "operatingSystem")]
    operating_system: String,
    #[serde(default, rename = "osImage")]
    os_image: String,
}

// K8s PersistentVolumeClaim (for cross-mapping with Longhorn volumes)

#[derive(Deserialize, Clone, Default)]
struct PvcResource {
    #[serde(default)]
    metadata: ObjectMeta,
    spec: Option<PvcSpec>,
}

#[derive(Deserialize, Clone, Default)]
struct PvcSpec {
    #[serde(default, rename = "volumeName")]
    volume_name: String,
}

#[derive(Serialize, Clone)]
struct NodeStat {
    name: String,
    cluster: String,
    role: String,
    ip: String,
    architecture: String,
    operating_system: String,
    ready: bool,
    disk_pressure: bool,
    memory_pressure: bool,
    cpu_millicores: u64,
    memory_bytes: u64,
    ephemeral_storage_bytes: u64,
}

/// Real host utilization from Prometheus node_exporter (via kubecost DaemonSet).
/// Available on worker nodes only; master has no node_exporter.
#[derive(Serialize, Clone, Default)]
struct NodeMetrics {
    cpu_percent: f64,
    mem_used_bytes: u64,
    mem_total_bytes: u64,
    mem_percent: f64,
    disk_used_bytes: u64,
    disk_total_bytes: u64,
    disk_percent: f64,
}

#[derive(Debug, Clone, Deserialize)]
struct ExternalNodeSpec {
    #[serde(default)]
    id: String,
    instance_host: String,
    #[serde(default)]
    endpoint_ip: Option<String>,
    fallback_name: String,
    cluster: String,
    role: String,
    cpu_millicores: u64,
    memory_bytes: u64,
    ephemeral_storage_bytes: u64,
    #[serde(default)]
    honeypot: bool,
    #[serde(default)]
    threats_path: Option<String>,
    #[serde(default)]
    timeseries_path: Option<String>,
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
    let secondary_live_monitor = if let Ok(path) = env::var("SECONDARY_KUBECONFIG_PATH") {
        let path = path.trim();
        if path.is_empty() {
            None
        } else {
            match LiveMonitor::from_kubeconfig(path).await {
                Ok(monitor) => {
                    println!("secondary K8s monitor enabled ({})", path);
                    Some(Arc::new(monitor))
                }
                Err(err) => {
                    eprintln!("secondary K8s monitor disabled: {}", err);
                    None
                }
            }
        }
    } else {
        None
    };
    let prometheus_monitor = Arc::new(PrometheusMonitor::new());

    let coroot_client = {
        let base_url = env::var("COROOT_BASE_URL")
            .unwrap_or_else(|_| "http://coroot.coroot.svc.cluster.local:8080".to_string());
        let project_id = env::var("COROOT_PROJECT_ID").unwrap_or_else(|_| "p3m78dle".to_string());
        match (env::var("COROOT_EMAIL"), env::var("COROOT_PASSWORD")) {
            (Ok(email), Ok(password)) => Some(Arc::new(CorootClient::new(
                base_url, email, password, project_id,
            ))),
            _ => {
                eprintln!("[warn] COROOT_EMAIL/COROOT_PASSWORD not set — coroot alerts disabled");
                None
            }
        }
    };

    let state = AppState {
        reports_root: Arc::new(reports_root),
        live_monitor,
        secondary_live_monitor,
        prometheus_monitor,
        coroot_client,
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
            .timeout(Duration::from_secs(10))
            .build()
            .map_err(|error| format!("build Kubernetes client: {}", error))?;

        Ok(Self {
            client,
            base_url: format!("https://{}:{}", host, port),
            cache: Arc::new(RwLock::new(None)),
        })
    }

    /// Build a LiveMonitor from an external kubeconfig file (client certificate auth).
    /// Used for secondary clusters (e.g., SSDNodes kubeadm cluster).
    async fn from_kubeconfig(path: &str) -> Result<Self, String> {
        let content = tokio::fs::read_to_string(path)
            .await
            .map_err(|e| format!("read kubeconfig {}: {}", path, e))?;
        let cfg: serde_yaml::Value =
            serde_yaml::from_str(&content).map_err(|e| format!("parse kubeconfig YAML: {}", e))?;

        let cluster = &cfg["clusters"][0]["cluster"];
        let server = cluster["server"]
            .as_str()
            .ok_or("kubeconfig: missing server URL")?
            .to_string();
        let ca_b64 = cluster["certificate-authority-data"]
            .as_str()
            .ok_or("kubeconfig: missing certificate-authority-data")?;
        let ca_pem = BASE64_STANDARD
            .decode(ca_b64)
            .map_err(|e| format!("decode CA cert: {}", e))?;

        let user = &cfg["users"][0]["user"];
        let cert_b64 = user["client-certificate-data"]
            .as_str()
            .ok_or("kubeconfig: missing client-certificate-data")?;
        let key_b64 = user["client-key-data"]
            .as_str()
            .ok_or("kubeconfig: missing client-key-data")?;
        let cert_pem = BASE64_STANDARD
            .decode(cert_b64)
            .map_err(|e| format!("decode client cert: {}", e))?;
        let key_pem = BASE64_STANDARD
            .decode(key_b64)
            .map_err(|e| format!("decode client key: {}", e))?;

        // reqwest Identity expects cert PEM followed by key PEM in the same buffer
        let mut identity_pem = cert_pem;
        identity_pem.extend_from_slice(&key_pem);

        let ca_cert =
            Certificate::from_pem(&ca_pem).map_err(|e| format!("parse CA cert: {}", e))?;
        let identity = reqwest::Identity::from_pem(&identity_pem)
            .map_err(|e| format!("parse client identity: {}", e))?;

        let client = Client::builder()
            .use_rustls_tls()
            .add_root_certificate(ca_cert)
            .identity(identity)
            .timeout(Duration::from_secs(10))
            .build()
            .map_err(|e| format!("build secondary K8s client: {}", e))?;

        Ok(Self {
            client,
            base_url: server,
            cache: Arc::new(RwLock::new(None)),
        })
    }

    async fn cached_or_refresh(&self) -> LiveOverview {
        self.overview_with_refresh_budget(Duration::from_secs(10))
            .await
    }

    /// Refresh live data with a bounded wait; reuse stale cache on timeout/error.
    pub(crate) async fn overview_with_refresh_budget(
        &self,
        refresh_budget: Duration,
    ) -> LiveOverview {
        if let Some(payload) = self.fresh_cache().await {
            return payload;
        }

        match tokio::time::timeout(refresh_budget, self.fetch_live()).await {
            Ok(Ok(payload)) => {
                *self.cache.write().await = Some(CachedLiveOverview {
                    fetched_at: Instant::now(),
                    payload: payload.clone(),
                });
                payload
            }
            Ok(Err(error)) => {
                if let Some(mut stale_payload) = self.cached_payload().await {
                    stale_payload.stale = true;
                    stale_payload.error = Some(error);
                    stale_payload
                } else {
                    unavailable_live_overview(error)
                }
            }
            Err(_) => {
                let message = format!("refresh timed out after {}s", refresh_budget.as_secs());
                if let Some(mut stale_payload) = self.cached_payload().await {
                    stale_payload.stale = true;
                    stale_payload.error = Some(message);
                    stale_payload
                } else {
                    unavailable_live_overview(message)
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
            node_metrics: HashMap::new(),
            services,
            incidents,
            metrics: unavailable_metrics_overview("metrics not fetched yet"),
            honeypot: HoneypotOverview::default(),
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

    pub(crate) async fn fetch_longhorn(&self) -> LonghornResponse {
        let now = unix_epoch_seconds();

        // Fetch PVCs and Longhorn volumes in parallel for cross-mapping
        let (vol_result, pvc_result) = tokio::join!(
            self.fetch_json::<KubeList<LonghornVolumeResource>>(
                "/apis/longhorn.io/v1beta2/namespaces/longhorn-system/volumes"
            ),
            self.fetch_json::<KubeList<PvcResource>>("/api/v1/persistentvolumeclaims")
        );

        let list = match vol_result {
            Ok(l) => l,
            Err(e) => {
                return LonghornResponse {
                    available: false,
                    volumes: vec![],
                    total: 0,
                    healthy: 0,
                    degraded: 0,
                    faulted: 0,
                    queried_at_epoch: now,
                    error: Some(e),
                }
            }
        };

        // Build map: volume_name (pvc-{UUID}) → (pvc_user_name, pvc_namespace)
        let pvc_map: HashMap<String, (String, String)> = pvc_result
            .unwrap_or_else(|_| KubeList { items: vec![] })
            .items
            .into_iter()
            .filter_map(|p| {
                let vol_name = p.spec?.volume_name;
                if vol_name.is_empty() {
                    return None;
                }
                let pvc_name = p.metadata.name?;
                let ns = p.metadata.namespace.unwrap_or_default();
                Some((vol_name, (pvc_name, ns)))
            })
            .collect();

        let volumes: Vec<LonghornVolume> = list
            .items
            .into_iter()
            .map(|v| {
                let status = v.status.unwrap_or_default();
                let spec = v.spec.unwrap_or_default();
                let size_bytes = spec.size.parse::<u64>().unwrap_or(0);
                let name = v.metadata.name.clone().unwrap_or_default();
                let (pvc_name, namespace) = pvc_map
                    .get(&name)
                    .cloned()
                    .unwrap_or_else(|| (name.clone(), "longhorn-system".to_string()));
                LonghornVolume {
                    pvc_name,
                    name,
                    namespace,
                    state: status.state,
                    robustness: status.robustness,
                    replicas_desired: spec.number_of_replicas,
                    size_bytes,
                    actual_size_bytes: status.actual_size,
                    node: status.current_node_id,
                }
            })
            .collect();

        let total = volumes.len();
        let healthy = volumes.iter().filter(|v| v.robustness == "healthy").count();
        let degraded = volumes
            .iter()
            .filter(|v| v.robustness == "degraded")
            .count();
        let faulted = volumes.iter().filter(|v| v.robustness == "faulted").count();
        LonghornResponse {
            available: true,
            volumes,
            total,
            healthy,
            degraded,
            faulted,
            queried_at_epoch: now,
            error: None,
        }
    }

    pub(crate) async fn fetch_workloads(&self) -> WorkloadsResponse {
        let now = unix_epoch_seconds();
        let (dep_result, sts_result, ds_result) = tokio::join!(
            self.fetch_json::<KubeList<DeploymentResource>>("/apis/apps/v1/deployments"),
            self.fetch_json::<KubeList<StatefulSetResource>>("/apis/apps/v1/statefulsets"),
            self.fetch_json::<KubeList<DaemonSetResource>>("/apis/apps/v1/daemonsets")
        );

        let mut workloads: Vec<WorkloadInfo> = vec![];

        fn first_image(tmpl: Option<&PodTemplateSpec>) -> String {
            tmpl.and_then(|t| t.spec.as_ref())
                .and_then(|s| s.containers.first())
                .map(|c| {
                    let img = c.image.as_str();
                    if let Some(pos) = img.rfind('/') {
                        img[pos + 1..].to_string()
                    } else {
                        img.to_string()
                    }
                })
                .unwrap_or_default()
        }

        fn workload_status(desired: i32, ready: i32) -> &'static str {
            if desired == 0 {
                "down"
            } else if ready >= desired {
                "healthy"
            } else if ready > 0 {
                "degraded"
            } else {
                "down"
            }
        }

        if let Ok(list) = dep_result {
            for d in list.items {
                let spec = d.spec.unwrap_or_default();
                let status = d.status.unwrap_or_default();
                let desired = spec.replicas.unwrap_or(0);
                let ready = status.ready_replicas.unwrap_or(0);
                let available = status.available_replicas.unwrap_or(0);
                let st = workload_status(desired, ready);
                workloads.push(WorkloadInfo {
                    name: d.metadata.name.unwrap_or_default(),
                    namespace: d.metadata.namespace.unwrap_or_default(),
                    kind: "Deployment".to_string(),
                    replicas_desired: desired,
                    replicas_ready: ready,
                    replicas_available: available,
                    image: first_image(spec.template.as_ref()),
                    status: st.to_string(),
                });
            }
        }

        if let Ok(list) = sts_result {
            for s in list.items {
                let spec = s.spec.unwrap_or_default();
                let status = s.status.unwrap_or_default();
                let desired = spec.replicas.unwrap_or(0);
                let ready = status.ready_replicas.unwrap_or(0);
                let available = status.current_replicas.unwrap_or(0);
                let st = workload_status(desired, ready);
                workloads.push(WorkloadInfo {
                    name: s.metadata.name.unwrap_or_default(),
                    namespace: s.metadata.namespace.unwrap_or_default(),
                    kind: "StatefulSet".to_string(),
                    replicas_desired: desired,
                    replicas_ready: ready,
                    replicas_available: available,
                    image: first_image(spec.template.as_ref()),
                    status: st.to_string(),
                });
            }
        }

        if let Ok(list) = ds_result {
            for d in list.items {
                let spec = d.spec.unwrap_or_default();
                let status = d.status.unwrap_or_default();
                let desired = status.desired_number_scheduled.unwrap_or(0);
                let ready = status.number_ready.unwrap_or(0);
                let available = status.number_available.unwrap_or(0);
                let st = workload_status(desired, ready);
                workloads.push(WorkloadInfo {
                    name: d.metadata.name.unwrap_or_default(),
                    namespace: d.metadata.namespace.unwrap_or_default(),
                    kind: "DaemonSet".to_string(),
                    replicas_desired: desired,
                    replicas_ready: ready,
                    replicas_available: available,
                    image: first_image(spec.template.as_ref()),
                    status: st.to_string(),
                });
            }
        }

        workloads.sort_by(|a, b| {
            let rank = |s: &str| match s {
                "down" => 0,
                "degraded" => 1,
                _ => 2,
            };
            rank(&a.status)
                .cmp(&rank(&b.status))
                .then(a.namespace.cmp(&b.namespace))
                .then(a.name.cmp(&b.name))
        });

        let total = workloads.len();
        let healthy = workloads.iter().filter(|w| w.status == "healthy").count();
        let degraded = workloads.iter().filter(|w| w.status == "degraded").count();
        let down = workloads.iter().filter(|w| w.status == "down").count();

        WorkloadsResponse {
            available: true,
            workloads,
            total,
            healthy,
            degraded,
            down,
            queried_at_epoch: now,
            error: None,
        }
    }

    pub(crate) async fn fetch_namespaces(&self) -> NamespacesResponse {
        let now = unix_epoch_seconds();
        match self
            .fetch_json::<KubeList<ResourceQuotaResource>>("/api/v1/resourcequotas")
            .await
        {
            Err(e) => NamespacesResponse {
                available: false,
                namespaces: vec![],
                total: 0,
                over_pressure: 0,
                queried_at_epoch: now,
                error: Some(e),
            },
            Ok(list) => {
                // Group by namespace (take first quota per namespace)
                let mut ns_map: HashMap<String, ResourceQuotaStatus> = HashMap::new();
                for rq in list.items {
                    let ns = rq.metadata.namespace.unwrap_or_default();
                    if let std::collections::hash_map::Entry::Vacant(e) = ns_map.entry(ns) {
                        if let Some(s) = rq.status {
                            e.insert(s);
                        }
                    }
                }

                fn get_q(map: &std::collections::BTreeMap<String, String>, key: &str) -> String {
                    map.get(key).cloned().unwrap_or_else(|| "—".to_string())
                }

                // Convert resource strings like "500m", "2", "512Mi", "1Gi" to f64 base units
                fn parse_cpu(s: &str) -> f64 {
                    if s == "—" || s.is_empty() {
                        return 0.0;
                    }
                    if let Some(m) = s.strip_suffix('m') {
                        m.parse::<f64>().unwrap_or(0.0) / 1000.0
                    } else {
                        s.parse::<f64>().unwrap_or(0.0)
                    }
                }

                fn parse_mem_bytes(s: &str) -> f64 {
                    if s == "—" || s.is_empty() {
                        return 0.0;
                    }
                    if let Some(v) = s.strip_suffix("Ki") {
                        return v.parse::<f64>().unwrap_or(0.0) * 1024.0;
                    }
                    if let Some(v) = s.strip_suffix("Mi") {
                        return v.parse::<f64>().unwrap_or(0.0) * 1024.0 * 1024.0;
                    }
                    if let Some(v) = s.strip_suffix("Gi") {
                        return v.parse::<f64>().unwrap_or(0.0) * 1024.0 * 1024.0 * 1024.0;
                    }
                    s.parse::<f64>().unwrap_or(0.0)
                }

                let mut namespaces: Vec<NamespaceQuota> = ns_map
                    .into_iter()
                    .map(|(ns, status)| {
                        let h = &status.hard;
                        let u = &status.used;

                        let cpu_lim_hard = get_q(h, "limits.cpu");
                        let cpu_lim_used = get_q(u, "limits.cpu");
                        let mem_lim_hard = get_q(h, "limits.memory");
                        let mem_lim_used = get_q(u, "limits.memory");

                        let cpu_pct = if cpu_lim_hard != "—" {
                            let hard = parse_cpu(&cpu_lim_hard);
                            let used = parse_cpu(&cpu_lim_used);
                            if hard > 0.0 {
                                (used / hard * 100.0).min(100.0)
                            } else {
                                0.0
                            }
                        } else {
                            0.0
                        };

                        let mem_pct = if mem_lim_hard != "—" {
                            let hard = parse_mem_bytes(&mem_lim_hard);
                            let used = parse_mem_bytes(&mem_lim_used);
                            if hard > 0.0 {
                                (used / hard * 100.0).min(100.0)
                            } else {
                                0.0
                            }
                        } else {
                            0.0
                        };

                        let pods_limit = h.get("pods").and_then(|s| s.parse().ok()).unwrap_or(0u32);
                        let pods_used = u.get("pods").and_then(|s| s.parse().ok()).unwrap_or(0u32);

                        NamespaceQuota {
                            name: ns,
                            cpu_request_used: get_q(u, "requests.cpu"),
                            cpu_request_limit: get_q(h, "requests.cpu"),
                            cpu_limit_used: cpu_lim_used,
                            cpu_limit_limit: cpu_lim_hard,
                            mem_request_used: get_q(u, "requests.memory"),
                            mem_request_limit: get_q(h, "requests.memory"),
                            mem_limit_used: mem_lim_used,
                            mem_limit_limit: mem_lim_hard,
                            pods_used,
                            pods_limit,
                            cpu_pressure_pct: (cpu_pct * 10.0).round() / 10.0,
                            mem_pressure_pct: (mem_pct * 10.0).round() / 10.0,
                        }
                    })
                    .collect();

                namespaces.sort_by(|a, b| {
                    b.cpu_pressure_pct
                        .partial_cmp(&a.cpu_pressure_pct)
                        .unwrap_or(std::cmp::Ordering::Equal)
                        .then(a.name.cmp(&b.name))
                });

                let total = namespaces.len();
                let over_pressure = namespaces
                    .iter()
                    .filter(|n| n.cpu_pressure_pct > 80.0 || n.mem_pressure_pct > 80.0)
                    .count();

                NamespacesResponse {
                    available: true,
                    namespaces,
                    total,
                    over_pressure,
                    queried_at_epoch: now,
                    error: None,
                }
            }
        }
    }

    pub(crate) async fn fetch_cronjobs(&self) -> CronJobsResponse {
        let now = unix_epoch_seconds();
        let (cj_result, job_result) = tokio::join!(
            self.fetch_json::<KubeList<CronJobResource>>("/apis/batch/v1/cronjobs"),
            self.fetch_json::<KubeList<JobResource>>("/apis/batch/v1/jobs")
        );

        match cj_result {
            Err(e) => CronJobsResponse {
                available: false,
                cronjobs: vec![],
                total: 0,
                healthy: 0,
                failed: 0,
                queried_at_epoch: now,
                error: Some(e),
            },
            Ok(cj_list) => {
                // Build map: (cronjob_ns, cronjob_name) → most recent job status
                let mut job_map: HashMap<(String, String), &JobResource> = HashMap::new();
                let jobs = job_result.unwrap_or_else(|_| KubeList { items: vec![] });

                for job in &jobs.items {
                    if let Some(owners) = &job
                        .metadata
                        .labels
                        .get("batch.kubernetes.io/cronjob-name")
                        .cloned()
                        .or_else(|| {
                            // Fallback: derive from job name (last part after hyphen-timestamp)
                            job.metadata.name.as_ref().map(|n| {
                                let parts: Vec<&str> = n.rsplitn(2, '-').collect();
                                if parts.len() == 2 {
                                    parts[1].to_string()
                                } else {
                                    n.clone()
                                }
                            })
                        })
                    {
                        let ns = job.metadata.namespace.clone().unwrap_or_default();
                        let key = (ns, owners.clone());
                        let entry = job_map.entry(key).or_insert(job);
                        // Keep the most recent job (latest startTime)
                        let existing_start = entry
                            .status
                            .as_ref()
                            .and_then(|s| s.start_time.as_deref())
                            .unwrap_or("");
                        let new_start = job
                            .status
                            .as_ref()
                            .and_then(|s| s.start_time.as_deref())
                            .unwrap_or("");
                        if new_start > existing_start {
                            *entry = job;
                        }
                    }
                }

                let cronjobs: Vec<CronJobInfo> = cj_list
                    .items
                    .into_iter()
                    .map(|cj| {
                        let ns = cj.metadata.namespace.clone().unwrap_or_default();
                        let cj_name = cj.metadata.name.clone().unwrap_or_default();
                        let spec = cj.spec.unwrap_or_default();
                        let status = cj.status.unwrap_or_default();
                        let active = status.active.len() as u32;

                        let last_job = job_map.get(&(ns.clone(), cj_name.clone()));
                        let (last_run_at, last_run_succeeded) = last_job
                            .map(|j| {
                                let s = j.status.as_ref();
                                let start = s.and_then(|s| s.start_time.clone());
                                let ok = s.map(|s| s.succeeded > 0 && s.failed == 0);
                                (start, ok)
                            })
                            .unwrap_or((None, None));

                        CronJobInfo {
                            name: cj_name,
                            namespace: ns,
                            schedule: spec.schedule,
                            active,
                            last_run_at,
                            last_run_succeeded,
                            last_schedule_time: status.last_schedule_time,
                            suspended: spec.suspend,
                        }
                    })
                    .collect();

                let total = cronjobs.len();
                let healthy = cronjobs
                    .iter()
                    .filter(|c| c.last_run_succeeded.unwrap_or(true) && !c.suspended)
                    .count();
                let failed = cronjobs
                    .iter()
                    .filter(|c| c.last_run_succeeded == Some(false))
                    .count();

                CronJobsResponse {
                    available: true,
                    cronjobs,
                    total,
                    healthy,
                    failed,
                    queried_at_epoch: now,
                    error: None,
                }
            }
        }
    }

    pub(crate) async fn fetch_ingresses(&self) -> IngressesResponse {
        let now = unix_epoch_seconds();
        match self
            .fetch_json::<KubeList<IngressResource>>("/apis/networking.k8s.io/v1/ingresses")
            .await
        {
            Err(e) => IngressesResponse {
                available: false,
                ingresses: vec![],
                total: 0,
                queried_at_epoch: now,
                error: Some(e),
            },
            Ok(list) => {
                let ingresses: Vec<IngressInfo> = list
                    .items
                    .into_iter()
                    .map(|ing| {
                        let spec = ing.spec.unwrap_or_default();
                        let hosts: Vec<String> =
                            spec.rules.iter().filter_map(|r| r.host.clone()).collect();
                        let tls = !spec.tls.is_empty();
                        let tls_secret = spec.tls.into_iter().find_map(|t| t.secret_name);
                        IngressInfo {
                            name: ing.metadata.name.unwrap_or_default(),
                            namespace: ing.metadata.namespace.unwrap_or_default(),
                            hosts,
                            tls,
                            tls_secret,
                            class: spec.ingress_class_name,
                        }
                    })
                    .collect();
                let total = ingresses.len();
                IngressesResponse {
                    available: true,
                    ingresses,
                    total,
                    queried_at_epoch: now,
                    error: None,
                }
            }
        }
    }

    pub(crate) async fn fetch_certificates(&self) -> CertificatesResponse {
        let now = unix_epoch_seconds();
        match self
            .fetch_json::<KubeList<CertResource>>("/apis/cert-manager.io/v1/certificates")
            .await
        {
            Err(e) => CertificatesResponse {
                available: false,
                certificates: vec![],
                total: 0,
                expiring_soon: 0,
                critical: 0,
                queried_at_epoch: now,
                error: Some(e),
            },
            Ok(list) => {
                let certificates: Vec<CertInfo> = list
                    .items
                    .into_iter()
                    .map(|c| {
                        let spec = c.spec.unwrap_or_default();
                        let status = c.status.unwrap_or_default();
                        let not_after = status.not_after.clone();
                        let days_remaining = not_after.as_deref().and_then(|s| {
                            parse_rfc3339_epoch(s).map(|exp| {
                                let diff = exp as i64 - now as i64;
                                diff / 86400
                            })
                        });
                        let ready = status
                            .conditions
                            .iter()
                            .any(|cond| cond.type_name == "Ready" && cond.status == "True");
                        CertInfo {
                            name: c.metadata.name.unwrap_or_default(),
                            namespace: c.metadata.namespace.unwrap_or_default(),
                            dns_names: spec.dns_names,
                            not_after,
                            ready,
                            days_remaining,
                        }
                    })
                    .collect();
                let total = certificates.len();
                let expiring_soon = certificates
                    .iter()
                    .filter(|c| c.days_remaining.map(|d| d < 60).unwrap_or(false))
                    .count();
                let critical = certificates
                    .iter()
                    .filter(|c| c.days_remaining.map(|d| d < 14).unwrap_or(false))
                    .count();
                CertificatesResponse {
                    available: true,
                    certificates,
                    total,
                    expiring_soon,
                    critical,
                    queried_at_epoch: now,
                    error: None,
                }
            }
        }
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

        let (
            cluster_cpu_percent_series,
            cluster_cpu_used_series,
            cluster_memory_percent_series,
            cluster_memory_used_series,
            restart_pressure_series,
            restart_events_last_hour,
            top_restarts,
            pod_cpu_series,
            pod_memory_series,
        ) = tokio::join!(
            self.query_range_points(
                cluster_cpu_percent_query,
                start,
                end,
                PROMETHEUS_STEP_SECONDS,
            ),
            self.query_range_points(cluster_cpu_used_query, start, end, PROMETHEUS_STEP_SECONDS),
            self.query_range_points(
                cluster_memory_percent_query,
                start,
                end,
                PROMETHEUS_STEP_SECONDS,
            ),
            self.query_range_points(
                cluster_memory_used_query,
                start,
                end,
                PROMETHEUS_STEP_SECONDS,
            ),
            self.query_range_points(&restart_pressure_query, start, end, PROMETHEUS_STEP_SECONDS),
            self.query_instant_value(&restart_last_hour_query),
            self.query_restart_hotspots(&top_restart_query),
            self.query_range_series(&pod_cpu_query, start, end, PROMETHEUS_STEP_SECONDS),
            self.query_range_series(&pod_memory_query, start, end, PROMETHEUS_STEP_SECONDS),
        );

        let cluster_cpu_percent_series = cluster_cpu_percent_series?;
        let cluster_cpu_used_series = cluster_cpu_used_series?;
        let cluster_memory_percent_series = cluster_memory_percent_series?;
        let cluster_memory_used_series = cluster_memory_used_series?;
        let restart_pressure_series = restart_pressure_series?;
        let restart_events_last_hour = restart_events_last_hour?;
        let top_restarts = top_restarts?;
        let pod_cpu_series = pod_cpu_series?;
        let pod_memory_series = pod_memory_series?;

        let service_metrics = services
            .iter()
            .map(|service| build_service_timeseries(service, &pod_cpu_series, &pod_memory_series))
            .collect();

        // Per-node historical data for sparkline pre-seeding (3 concurrent range queries)
        let node_cpu_query =
            r#"100 - (avg by (node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)"#;
        let node_mem_query = r#"100 * (1 - avg by (node) (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))"#;
        let node_disk_query = r#"100 * (1 - avg by (node) (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}))"#;

        let (node_cpu_res, node_mem_res, node_disk_res) = tokio::join!(
            self.query_range_series(node_cpu_query, start, end, PROMETHEUS_STEP_SECONDS),
            self.query_range_series(node_mem_query, start, end, PROMETHEUS_STEP_SECONDS),
            self.query_range_series(node_disk_query, start, end, PROMETHEUS_STEP_SECONDS),
        );
        let node_history = build_node_history(
            node_cpu_res.unwrap_or_default(),
            node_mem_res.unwrap_or_default(),
            node_disk_res.unwrap_or_default(),
        );

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
            node_history,
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

    /// Fetch real host utilization from Prometheus node_exporter (via kubecost DaemonSet).
    /// Returns a map keyed by K8s node name (e.g. "k8s-node-1").
    /// Nodes without node_exporter (e.g. k8s-master) are simply absent from the map.
    pub(crate) async fn fetch_node_metrics(&self) -> HashMap<String, NodeMetrics> {
        // Run instant queries concurrently.
        let cpu_q = r#"100 - (avg by (node, instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)"#;
        let mem_avail_q = "node_memory_MemAvailable_bytes";
        let mem_total_q = "node_memory_MemTotal_bytes";
        let disk_avail_q = r#"node_filesystem_avail_bytes{mountpoint="/"}"#;
        let disk_total_q = r#"node_filesystem_size_bytes{mountpoint="/"}"#;
        let uname_q = "node_uname_info";

        let (cpu_res, mem_avail_res, mem_total_res, disk_avail_res, disk_total_res, uname_res) = tokio::join!(
            self.query_instant_series(cpu_q),
            self.query_instant_series(mem_avail_q),
            self.query_instant_series(mem_total_q),
            self.query_instant_series(disk_avail_q),
            self.query_instant_series(disk_total_q),
            self.query_instant_series(uname_q),
        );

        let cpu_map = series_to_node_map(cpu_res.unwrap_or_default());
        let mem_avail_map = series_to_node_map(mem_avail_res.unwrap_or_default());
        let mem_total_map = series_to_node_map(mem_total_res.unwrap_or_default());
        let disk_avail_map = series_to_node_map(disk_avail_res.unwrap_or_default());
        let disk_total_map = series_to_node_map(disk_total_res.unwrap_or_default());

        let (instance_to_nodename, nodename_to_instance) =
            build_instance_nodename_aliases(&uname_res.unwrap_or_default());

        // Collect all node names seen across any metric.
        let mut node_names: BTreeSet<String> = BTreeSet::new();
        for map in [
            &cpu_map,
            &mem_avail_map,
            &mem_total_map,
            &disk_avail_map,
            &disk_total_map,
        ] {
            node_names.extend(map.keys().map(|key| {
                canonical_node_name(key, &instance_to_nodename).unwrap_or_else(|| key.clone())
            }));
        }

        let map = node_names
            .into_iter()
            .filter_map(|node| {
                let cpu_percent = metric_value_for_node(&cpu_map, &node, &nodename_to_instance);
                let mem_avail =
                    metric_value_for_node(&mem_avail_map, &node, &nodename_to_instance) as u64;
                let mem_total =
                    metric_value_for_node(&mem_total_map, &node, &nodename_to_instance) as u64;
                let disk_avail =
                    metric_value_for_node(&disk_avail_map, &node, &nodename_to_instance) as u64;
                let disk_total =
                    metric_value_for_node(&disk_total_map, &node, &nodename_to_instance) as u64;

                if mem_total == 0 && disk_total == 0 {
                    return None; // skip empty entries
                }

                let mem_used = mem_total.saturating_sub(mem_avail);
                let mem_percent = if mem_total > 0 {
                    (mem_used as f64 / mem_total as f64) * 100.0
                } else {
                    0.0
                };
                let disk_used = disk_total.saturating_sub(disk_avail);
                let disk_percent = if disk_total > 0 {
                    (disk_used as f64 / disk_total as f64) * 100.0
                } else {
                    0.0
                };

                Some((
                    node,
                    NodeMetrics {
                        cpu_percent,
                        mem_used_bytes: mem_used,
                        mem_total_bytes: mem_total,
                        mem_percent,
                        disk_used_bytes: disk_used,
                        disk_total_bytes: disk_total,
                        disk_percent,
                    },
                ))
            })
            .collect();

        alias_external_node_metrics(map)
    }

    pub(crate) async fn fetch_external_node_stats(&self) -> Vec<NodeStat> {
        let uname_series = self
            .query_instant_series("node_uname_info")
            .await
            .unwrap_or_default();

        let mut uname_by_instance: HashMap<String, (String, String, String)> = HashMap::new();
        for series in uname_series {
            let instance = series
                .metric
                .get("instance")
                .map(|value| extract_instance_host(value));
            let Some(instance_host) = instance else {
                continue;
            };

            let nodename = series
                .metric
                .get("nodename")
                .filter(|value| !value.is_empty())
                .cloned()
                .unwrap_or_else(|| {
                    fallback_name_for_instance(&instance_host)
                        .unwrap_or_else(|| instance_host.clone())
                });
            let arch = series
                .metric
                .get("machine")
                .filter(|value| !value.is_empty())
                .cloned()
                .unwrap_or_else(|| "unknown".to_string());
            let os = match (
                series.metric.get("sysname").map(String::as_str),
                series.metric.get("release").map(String::as_str),
            ) {
                (Some(sysname), Some(release)) if !sysname.is_empty() && !release.is_empty() => {
                    format!("{} {}", sysname, release)
                }
                (Some(sysname), _) if !sysname.is_empty() => sysname.to_string(),
                _ => "unknown".to_string(),
            };

            uname_by_instance.insert(instance_host, (nodename, arch, os));
        }

        external_node_specs()
            .iter()
            .map(|spec| {
                let lookup_hosts = external_lookup_hosts(spec);
                let (name, architecture, operating_system) = lookup_hosts
                    .iter()
                    .find_map(|host| uname_by_instance.get(host.as_str()).cloned())
                    .unwrap_or_else(|| {
                        (
                            spec.fallback_name.to_string(),
                            "unknown".to_string(),
                            "unknown".to_string(),
                        )
                    });

                NodeStat {
                    name,
                    cluster: spec.cluster.to_string(),
                    role: spec.role.to_string(),
                    ip: spec.instance_host.to_string(),
                    architecture,
                    operating_system,
                    ready: false,
                    disk_pressure: false,
                    memory_pressure: false,
                    cpu_millicores: spec.cpu_millicores,
                    memory_bytes: spec.memory_bytes,
                    ephemeral_storage_bytes: spec.ephemeral_storage_bytes,
                }
            })
            .collect()
    }

    pub(crate) async fn fetch_honeypot_overview(&self) -> HoneypotOverview {
        let specs: Vec<&ExternalNodeSpec> = external_node_specs()
            .iter()
            .filter(|spec| spec.honeypot)
            .collect();

        if specs.is_empty() {
            return HoneypotOverview::default();
        }

        let client = match Client::builder()
            .timeout(Duration::from_secs(8))
            .danger_accept_invalid_certs(true)
            .build()
        {
            Ok(client) => client,
            Err(error) => {
                let message = format!("build honeypot client: {}", error);
                return HoneypotOverview {
                    available: false,
                    nodes: specs
                        .into_iter()
                        .map(|spec| honeypot_node_error(spec, &message))
                        .collect(),
                };
            }
        };

        let mut nodes = Vec::with_capacity(specs.len());
        for spec in specs {
            nodes.push(fetch_honeypot_node(&client, spec).await);
        }

        HoneypotOverview {
            available: nodes.iter().any(|node| node.available),
            nodes,
        }
    }
}

async fn fetch_honeypot_node(client: &Client, spec: &ExternalNodeSpec) -> HoneypotNodeStats {
    let summary_path = spec
        .threats_path
        .as_deref()
        .filter(|value| !value.is_empty())
        .unwrap_or("/internal/threats-summary");
    let timeseries_path = spec
        .timeseries_path
        .as_deref()
        .filter(|value| !value.is_empty())
        .unwrap_or("/internal/threats-timeseries");
    let summary_url = honeypot_api_url(spec, summary_path);
    let timeseries_url = honeypot_api_url(spec, timeseries_path);

    let (summary_result, timeseries_result) = tokio::join!(
        client.get(&summary_url).send(),
        client.get(&timeseries_url).send(),
    );

    let timeseries = match timeseries_result {
        Ok(response) if response.status().is_success() => response
            .json::<QdbbackThreatTimeseries>()
            .await
            .unwrap_or_default(),
        _ => QdbbackThreatTimeseries::default(),
    };

    match summary_result {
        Ok(response) => {
            if !response.status().is_success() {
                return honeypot_node_error(
                    spec,
                    &format!("honeypot API status {}", response.status()),
                );
            }

            match response.json::<QdbbackThreatSummary>().await {
                Ok(summary) => HoneypotNodeStats {
                    id: honeypot_node_id(spec),
                    cluster: spec.cluster.clone(),
                    instance_host: spec.instance_host.clone(),
                    available: true,
                    total: summary.total,
                    last24h: summary.last24h,
                    classified: summary.classified,
                    unclassified: summary.unclassified,
                    top_tags: summary.top_tags,
                    requests_24h: timeseries.requests_24h,
                    requests_7d: timeseries.requests_7d,
                    refreshed_at_epoch: unix_epoch_seconds(),
                    error: None,
                },
                Err(error) => {
                    honeypot_node_error(spec, &format!("decode honeypot JSON: {}", error))
                }
            }
        }
        Err(error) => honeypot_node_error(spec, &format!("request honeypot API: {}", error)),
    }
}

fn honeypot_api_url(spec: &ExternalNodeSpec, path: &str) -> String {
    format!(
        "https://{}/{}",
        spec.instance_host,
        path.trim_start_matches('/')
    )
}

fn honeypot_node_id(spec: &ExternalNodeSpec) -> String {
    if spec.id.is_empty() {
        spec.fallback_name.clone()
    } else {
        spec.id.clone()
    }
}

fn honeypot_node_error(spec: &ExternalNodeSpec, message: &str) -> HoneypotNodeStats {
    HoneypotNodeStats {
        id: honeypot_node_id(spec),
        cluster: spec.cluster.clone(),
        instance_host: spec.instance_host.clone(),
        available: false,
        refreshed_at_epoch: unix_epoch_seconds(),
        error: Some(message.to_string()),
        ..HoneypotNodeStats::default()
    }
}

/// Convert a list of PrometheusSeries to a map: node_label → f64 value.
fn series_to_node_map(series: Vec<PrometheusSeries>) -> HashMap<String, f64> {
    series
        .into_iter()
        .filter_map(|s| {
            let node = if let Some(n) = s.metric.get("node") {
                n.clone()
            } else if let Some(nodename) = s.metric.get("nodename") {
                nodename.clone()
            } else if let Some(inst) = s.metric.get("instance") {
                extract_instance_host(inst)
            } else {
                return None;
            };
            let (_, val_str) = s.value?;
            Some((node, parse_prometheus_value(&val_str)))
        })
        .collect()
}

fn extract_instance_host(instance: &str) -> String {
    instance
        .split_once(':')
        .map(|(host, _)| host)
        .unwrap_or(instance)
        .trim_matches('[')
        .trim_matches(']')
        .to_string()
}

fn fallback_name_for_instance(instance_host: &str) -> Option<String> {
    external_node_specs()
        .iter()
        .find(|spec| {
            spec.instance_host == instance_host
                || spec
                    .endpoint_ip
                    .as_deref()
                    .is_some_and(|endpoint| endpoint == instance_host)
        })
        .map(|spec| spec.fallback_name.clone())
}

fn external_lookup_hosts(spec: &ExternalNodeSpec) -> Vec<String> {
    let mut hosts = vec![spec.instance_host.clone()];
    if let Some(endpoint_ip) = spec.endpoint_ip.as_ref() {
        if !hosts.iter().any(|host| host == endpoint_ip) {
            hosts.push(endpoint_ip.clone());
        }
    }
    hosts
}

fn alias_external_node_metrics(
    mut metrics: HashMap<String, NodeMetrics>,
) -> HashMap<String, NodeMetrics> {
    for spec in external_node_specs() {
        let source_key = metrics
            .keys()
            .find(|key| {
                key.as_str() == spec.fallback_name.as_str()
                    || key.as_str() == spec.instance_host.as_str()
                    || spec
                        .endpoint_ip
                        .as_deref()
                        .is_some_and(|endpoint| key.as_str() == endpoint)
                    || key.contains(&spec.fallback_name)
                    || spec
                        .endpoint_ip
                        .as_deref()
                        .is_some_and(|endpoint| key.contains(endpoint))
            })
            .cloned();

        let Some(source_key) = source_key else {
            continue;
        };
        let Some(entry) = metrics.get(&source_key).cloned() else {
            continue;
        };
        metrics.insert(spec.fallback_name.clone(), entry.clone());
        metrics.insert(spec.instance_host.clone(), entry);
    }
    metrics
}

fn node_has_metrics(node: &NodeStat, metrics: &HashMap<String, NodeMetrics>) -> bool {
    if metrics.contains_key(&node.name) || metrics.contains_key(&node.ip) {
        return true;
    }

    external_node_specs().iter().any(|spec| {
        (spec.fallback_name == node.name || spec.instance_host == node.ip)
            && (metrics.contains_key(&spec.fallback_name)
                || metrics.contains_key(&spec.instance_host)
                || spec
                    .endpoint_ip
                    .as_deref()
                    .is_some_and(|endpoint| metrics.contains_key(endpoint)))
    })
}

fn build_instance_nodename_aliases(
    series: &[PrometheusSeries],
) -> (HashMap<String, String>, HashMap<String, String>) {
    let mut instance_to_nodename = HashMap::new();
    let mut nodename_to_instance = HashMap::new();

    for entry in series {
        let Some(instance) = entry.metric.get("instance") else {
            continue;
        };
        let Some(nodename) = entry.metric.get("nodename") else {
            continue;
        };
        if nodename.is_empty() {
            continue;
        }

        let host = extract_instance_host(instance);
        instance_to_nodename.insert(host.clone(), nodename.clone());
        nodename_to_instance.insert(nodename.clone(), host);
    }

    for spec in external_node_specs() {
        nodename_to_instance
            .entry(spec.fallback_name.clone())
            .or_insert_with(|| {
                spec.endpoint_ip
                    .clone()
                    .unwrap_or_else(|| spec.instance_host.clone())
            });
        instance_to_nodename
            .entry(spec.instance_host.clone())
            .or_insert_with(|| spec.fallback_name.clone());
        if let Some(endpoint_ip) = spec.endpoint_ip.as_ref() {
            instance_to_nodename
                .entry(endpoint_ip.clone())
                .or_insert_with(|| spec.fallback_name.clone());
            nodename_to_instance
                .entry(spec.fallback_name.clone())
                .or_insert_with(|| endpoint_ip.clone());
        }
    }

    (instance_to_nodename, nodename_to_instance)
}

fn canonical_node_name(
    key: &str,
    instance_to_nodename: &HashMap<String, String>,
) -> Option<String> {
    if let Some(alias) = instance_to_nodename.get(key) {
        return Some(alias.clone());
    }

    fallback_name_for_instance(key)
}

fn metric_value_for_node(
    map: &HashMap<String, f64>,
    node_name: &str,
    nodename_to_instance: &HashMap<String, String>,
) -> f64 {
    map.get(node_name)
        .copied()
        .or_else(|| {
            nodename_to_instance
                .get(node_name)
                .and_then(|instance| map.get(instance).copied())
        })
        .unwrap_or(0.0)
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

    // Only flag as degraded from restarts if the cumulative count exceeds a per-pod
    // threshold. A single historical restart on an otherwise healthy pod is normal;
    // genuine crash-loops are already caught above via has_blocker (CrashLoopBackOff).
    let restart_threshold = (rollup.total as i32).max(1) * 5;
    if status == "healthy" && rollup.restart_count > restart_threshold {
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

            let ip = node_internal_ip(node).unwrap_or_else(|| "unknown".to_string());
            let architecture = node
                .status
                .as_ref()
                .and_then(|status| status.node_info.as_ref())
                .map(|info| info.architecture.clone())
                .filter(|value| !value.is_empty())
                .unwrap_or_else(|| "unknown".to_string());
            let operating_system = node
                .status
                .as_ref()
                .and_then(|status| status.node_info.as_ref())
                .map(|info| {
                    if !info.os_image.is_empty() {
                        info.os_image.clone()
                    } else {
                        info.operating_system.clone()
                    }
                })
                .filter(|value| !value.is_empty())
                .unwrap_or_else(|| "unknown".to_string());

            NodeStat {
                name,
                cluster: "OCI-K8S".to_string(),
                role,
                ip,
                architecture,
                operating_system,
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
        .map(|(ts, value)| MetricPoint {
            timestamp: ts,
            value,
        })
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
            timestamp: timestamp.round() as u64,
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

fn node_internal_ip(node: &NodeResource) -> Option<String> {
    node.status.as_ref().and_then(|status| {
        status
            .addresses
            .iter()
            .find(|address| address.type_name.as_deref() == Some("InternalIP"))
            .and_then(|address| address.address.clone())
    })
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
        node_metrics: HashMap::new(),
        services: Vec::new(),
        incidents: Vec::new(),
        metrics: unavailable_metrics_overview("prometheus metrics unavailable"),
        honeypot: HoneypotOverview::default(),
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
        node_history: HashMap::new(),
        error: Some(reason.into()),
    }
}

/// Build per-node NodeTimeseries from Prometheus range query results.
fn build_node_history(
    cpu_series: Vec<PrometheusSeries>,
    mem_series: Vec<PrometheusSeries>,
    disk_series: Vec<PrometheusSeries>,
) -> HashMap<String, NodeTimeseries> {
    let mut map: HashMap<String, NodeTimeseries> = HashMap::new();
    for s in cpu_series {
        if let Some(node) = s.metric.get("node") {
            map.entry(node.clone()).or_default().cpu_percent_series =
                convert_values_to_points(&s.values);
        }
    }
    for s in mem_series {
        if let Some(node) = s.metric.get("node") {
            map.entry(node.clone()).or_default().mem_percent_series =
                convert_values_to_points(&s.values);
        }
    }
    for s in disk_series {
        if let Some(node) = s.metric.get("node") {
            map.entry(node.clone()).or_default().disk_percent_series =
                convert_values_to_points(&s.values);
        }
    }
    map
}

pub(crate) fn unix_epoch_seconds() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

/// Parse an RFC3339 UTC timestamp like "2026-07-31T13:18:55Z" to Unix epoch seconds.
/// Handles only the `Z` / `+00:00` UTC suffix (sufficient for cert-manager notAfter).
fn parse_rfc3339_epoch(s: &str) -> Option<u64> {
    let s = s
        .trim_end_matches('Z')
        .trim_end_matches("+00:00")
        .trim_end_matches("-00:00");
    let (date_part, time_part) = s.split_once('T')?;
    let mut d_iter = date_part.split('-');
    let y: i64 = d_iter.next()?.parse().ok()?;
    let mo: i64 = d_iter.next()?.parse().ok()?;
    let d: i64 = d_iter.next()?.parse().ok()?;
    let mut t_iter = time_part.split(':');
    let h: i64 = t_iter.next()?.parse().ok()?;
    let mi: i64 = t_iter.next()?.parse().ok()?;
    let se: i64 = t_iter.next().and_then(|v| v.parse().ok()).unwrap_or(0);
    // Julian Day Number → Unix epoch
    let a = (14 - mo) / 12;
    let yy = y + 4800 - a;
    let mm = mo + 12 * a - 3;
    let jdn = d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045;
    let unix_day = jdn - 2_440_588; // Julian day of 1970-01-01
    let epoch = unix_day * 86400 + h * 3600 + mi * 60 + se;
    if epoch >= 0 {
        Some(epoch as u64)
    } else {
        None
    }
}

fn json_error(status: StatusCode, message: &str, detail: &str) -> Response {
    (status, Json(json!({ "error": message, "detail": detail }))).into_response()
}
