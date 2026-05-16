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

export interface LiveOverview {
  available: boolean;
  stale: boolean;
  error?: string;
  refresh_interval_seconds: number;
  refreshed_at_epoch: number;
  summary: LiveSummary;
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
