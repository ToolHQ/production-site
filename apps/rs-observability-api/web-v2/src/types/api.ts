// Tipos para /api/live/overview

export interface TimeSeriesPoint {
  timestamp: number;
  value: number;
}

export interface ClusterMetrics {
  cpu_percent_latest: number;
  cpu_cores_used_latest: number;
  memory_percent_latest: number;
  memory_bytes_used_latest: number;
  restart_events_last_hour: number;
  cpu_percent_series: TimeSeriesPoint[];
  memory_percent_series: TimeSeriesPoint[];
  restart_pressure_series: TimeSeriesPoint[];
}

export interface ServiceMetrics {
  id: string;
  label: string;
  cpu_cores_latest: number;
  memory_bytes_latest: number;
  cpu_series: TimeSeriesPoint[];
  memory_series: TimeSeriesPoint[];
}

export interface RestartHotspot {
  pod: string;
  namespace: string;
  restarts_last_hour: number;
}

/** Per-node historical sparkline data from Prometheus (last 60m, 5m resolution). */
export interface NodeHistory {
  cpu_percent_series: TimeSeriesPoint[];
  mem_percent_series: TimeSeriesPoint[];
  disk_percent_series: TimeSeriesPoint[];
}

export interface MetricsData {
  available: boolean;
  stale: boolean;
  error?: string;
  window_minutes: number;
  refresh_interval_seconds?: number;
  refreshed_at_epoch: number;
  cluster: ClusterMetrics;
  services: ServiceMetrics[];
  top_restarts: RestartHotspot[];
  /** Per-node sparkline history. Keyed by node name. Populated when Prometheus is available. */
  node_history?: Record<string, NodeHistory>;
}

export interface Incident {
  resource: string;
  namespace: string;
  message: string;
  severity: 'critical' | 'warning';
}

export interface ServiceStatus {
  id: string;
  label: string;
  status: 'healthy' | 'degraded' | 'down' | 'telemetry';
  message: string;
  namespace: string;
  workload_kind: string;
  workload_name: string;
  ready: number;
  desired: number;
  running_pods: number;
  pods_total: number;
  restart_count: number;
  route?: string;
}

export interface LiveSummary {
  critical_services: number;
  healthy_services: number;
  down_services: number;
  degraded_services: number;
  running_pods: number;
  total_pods: number;
  restarting_pods: number;
  nodes_ready: number;
  nodes_total: number;
  affected_namespaces: number;
}

export interface NodeStat {
  name: string;
  role: 'control-plane' | 'worker';
  ready: boolean;
  disk_pressure: boolean;
  memory_pressure: boolean;
  /** Allocatable CPU em millicores (ex: 940 = 0.94 vCPU) */
  cpu_millicores: number;
  /** Allocatable memory em bytes */
  memory_bytes: number;
  /** Allocatable ephemeral-storage em bytes */
  ephemeral_storage_bytes: number;
}

/** Real host utilization from Prometheus node_exporter (workers only). */
export interface NodeMetrics {
  cpu_percent: number;
  mem_used_bytes: number;
  mem_total_bytes: number;
  mem_percent: number;
  disk_used_bytes: number;
  disk_total_bytes: number;
  disk_percent: number;
}

export interface LiveOverview {
  available: boolean;
  stale: boolean;
  error?: string;
  refresh_interval_seconds: number;
  refreshed_at_epoch: number;
  summary: LiveSummary;
  nodes: NodeStat[];
  /** Real host utilization per node. Only present for nodes with node_exporter. */
  node_metrics: Record<string, NodeMetrics>;
  services: ServiceStatus[];
  incidents: Incident[];
  metrics: MetricsData;
}

// Tipos para /api/catalog/summary e /api/catalog

export interface SnapshotSummary {
  generated_at: string;
  app_count: number;
  deployable_app_count: number;
  missing_deploy_script_count: number;
  component_count: number;
  cluster_workload_count: number;
  repo_only_app_count: number;
  repo_only_component_count: number;
  cluster_only_count: number;
  undocumented_count: number;
  app_languages: Array<{ language: string; count: number }>;
}

export interface CatalogApp {
  name: string;
  description?: string;
  language?: string;
  framework?: string;
  deploy_script?: string;
  exposed_port?: number;
  readiness_missing?: string;
  deploy_readiness: 'deployable' | 'partial' | 'wip';
}

export interface CatalogData {
  apps: CatalogApp[];
}

// Tipos para /api/reports

export interface Artifact {
  id: string;
  kind: string;
  label: string;
  href: string;
  size_bytes: number;
}

export interface ReportsData {
  artifacts: Artifact[];
}

// Tipos para /api/coroot-alerts

export interface CorootAlert {
  id: string;
  rule_id: string;
  rule_name: string;
  /** Format: "{project_id}:{namespace}:{Kind}:{name}" */
  application_id: string;
  severity: string;
  summary: string;
  /** Milliseconds epoch */
  opened_at: number;
  /** Duration in milliseconds */
  duration: number;
  /** Alert category e.g. "Net", "Instances", "Logs" */
  report: string | null;
}

export interface CorootAlertsData {
  available: boolean;
  alerts: CorootAlert[];
  total: number;
  queried_at_epoch: number;
  error?: string;
}
