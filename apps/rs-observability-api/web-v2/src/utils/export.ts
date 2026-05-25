import type { LiveOverview, MetricsData } from '../types/api';
import {
  buildFleetOverviewRows,
  fleetActivityMetrics,
  fleetOverviewToCSV,
  honeypotActivityMetrics,
  type FleetPeriod,
} from './fleetOverview';

function nowIso(): string {
  return new Date().toISOString().slice(0, 19).replace('T', '_');
}

function download(content: string, filename: string, mime: string): void {
  const blob = new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

function fleetRowsForExport(live: LiveOverview | null) {
  return buildFleetOverviewRows(live?.nodes ?? [], live?.honeypot?.nodes ?? []);
}

// ── Build flat snapshot object ────────────────────────────────
function buildSnapshot(
  live: LiveOverview | null,
  metrics: MetricsData | null,
  period: FleetPeriod = '24h',
) {
  const ts = nowIso();
  const fleetRows = fleetRowsForExport(live);
  const honeypotNodes = live?.honeypot?.nodes ?? [];

  return {
    exported_at: ts,
    fleet_period: period,
    cluster: {
      nodes: (live?.nodes ?? []).map((n) => {
        const m = live?.node_metrics?.[n.name];
        return {
          name: n.name,
          cluster: n.cluster,
          role: n.role,
          ip: n.ip,
          architecture: n.architecture,
          operating_system: n.operating_system,
          ready: n.ready,
          disk_pressure: n.disk_pressure,
          memory_pressure: n.memory_pressure,
          cpu_millicores: n.cpu_millicores,
          memory_bytes: n.memory_bytes,
          ephemeral_storage_bytes: n.ephemeral_storage_bytes,
          cpu_percent: m?.cpu_percent ?? null,
          mem_percent: m?.mem_percent ?? null,
          disk_percent: m?.disk_percent ?? null,
          mem_used_bytes: m?.mem_used_bytes ?? null,
          mem_total_bytes: m?.mem_total_bytes ?? null,
          disk_used_bytes: m?.disk_used_bytes ?? null,
          disk_total_bytes: m?.disk_total_bytes ?? null,
        };
      }),
      incidents: (live?.incidents ?? []).map((i) => ({
        resource: i.resource,
        namespace: i.namespace,
        severity: i.severity,
        message: i.message,
      })),
    },
    fleet: {
      period,
      rows: fleetRows.map((row) => {
        const activity = fleetActivityMetrics(row, period);
        return {
          status: row.status,
          name: row.name,
          subtitle: row.subtitle ?? null,
          cluster: row.cluster,
          ip: row.ip,
          asn: row.asn,
          asn_label: row.asnLabel,
          total_requests: row.totalRequests,
          activity_label: activity.label,
          activity_count: activity.value,
          classified: row.classified,
          is_honeypot: row.isHoneypot,
          monitor_href: row.monitorHref ?? null,
          requests_24h: row.requests24h,
          requests_7d: row.requests7d,
        };
      }),
    },
    honeypot: {
      available: live?.honeypot?.available ?? false,
      nodes: honeypotNodes.map((stats) => {
        const activity = honeypotActivityMetrics(stats, period);
        return {
          id: stats.id,
          cluster: stats.cluster,
          instance_host: stats.instance_host,
          available: stats.available,
          total: stats.total,
          last24h: stats.last24h,
          classified: stats.classified,
          unclassified: stats.unclassified,
          top_tags: stats.top_tags,
          activity_label: activity.label,
          activity_count: activity.value,
          requests_24h: stats.requests_24h ?? [],
          requests_7d: stats.requests_7d ?? [],
          refreshed_at_epoch: stats.refreshed_at_epoch,
          error: stats.error ?? null,
        };
      }),
    },
    prometheus: metrics?.available
      ? {
          window_minutes: metrics.window_minutes,
          cpu_percent_latest: metrics.cluster.cpu_percent_latest,
          memory_percent_latest: metrics.cluster.memory_percent_latest,
          restart_events_last_hour: metrics.cluster.restart_events_last_hour,
          top_restarts: metrics.top_restarts,
          services: metrics.services.map((s) => ({
            id: s.id,
            label: s.label,
            cpu_cores_latest: s.cpu_cores_latest,
            memory_bytes_latest: s.memory_bytes_latest,
          })),
        }
      : null,
  };
}

// ── CSV: nodes table ─────────────────────────────────────────
function nodesToCSV(live: LiveOverview | null): string {
  const headers = [
    'name', 'cluster', 'role', 'ip', 'architecture', 'operating_system', 'ready', 'disk_pressure', 'memory_pressure',
    'cpu_percent', 'mem_percent', 'disk_percent',
    'cpu_millicores', 'mem_total_gib', 'disk_total_gib',
  ];
  const rows = (live?.nodes ?? []).map((n) => {
    const m = live?.node_metrics?.[n.name];
    return [
      n.name,
      n.cluster,
      n.role,
      n.ip,
      n.architecture,
      `"${n.operating_system.replace(/"/g, '""')}"`,
      n.ready ? 'true' : 'false',
      n.disk_pressure ? 'true' : 'false',
      n.memory_pressure ? 'true' : 'false',
      m?.cpu_percent?.toFixed(1) ?? '',
      m?.mem_percent?.toFixed(1) ?? '',
      m?.disk_percent?.toFixed(1) ?? '',
      n.cpu_millicores,
      m ? (m.mem_total_bytes / (1024 ** 3)).toFixed(2) : '',
      m ? (m.disk_total_bytes / (1024 ** 3)).toFixed(2) : '',
    ].join(',');
  });
  return [headers.join(','), ...rows].join('\n');
}

function incidentsToCSV(live: LiveOverview | null): string {
  const headers = ['resource', 'namespace', 'severity', 'message'];
  const rows = (live?.incidents ?? []).map((i) =>
    [i.resource, i.namespace, i.severity, `"${i.message.replace(/"/g, '""')}"`].join(',')
  );
  return [headers.join(','), ...rows].join('\n');
}

function servicesToCSV(metrics: MetricsData | null): string {
  if (!metrics?.available) return 'id,label,cpu_cores_latest,memory_mb_latest\n(no Prometheus data)';
  const headers = ['id', 'label', 'cpu_cores_latest', 'memory_mb_latest'];
  const rows = metrics.services.map((s) =>
    [s.id, s.label, s.cpu_cores_latest.toFixed(3), (s.memory_bytes_latest / (1024 ** 2)).toFixed(1)].join(',')
  );
  return [headers.join(','), ...rows].join('\n');
}

// ── Public API ───────────────────────────────────────────────
export function exportJSON(
  live: LiveOverview | null,
  metrics: MetricsData | null,
  period: FleetPeriod = '24h',
): void {
  const snapshot = buildSnapshot(live, metrics, period);
  const json = JSON.stringify(snapshot, null, 2);
  download(json, `cluster-snapshot_${nowIso()}.json`, 'application/json');
}

export function exportCSVBundle(
  live: LiveOverview | null,
  metrics: MetricsData | null,
  period: FleetPeriod = '24h',
): void {
  const fleetRows = fleetRowsForExport(live);
  const periodLabel = period === '7d' ? '7d' : '24h';
  const parts = [
    `# FLEET OVERVIEW (period: ${periodLabel})`,
    fleetOverviewToCSV(fleetRows, period),
    '',
    '# NODES',
    nodesToCSV(live),
    '',
    '# INCIDENTS',
    incidentsToCSV(live),
    '',
    '# SERVICES (Prometheus)',
    servicesToCSV(metrics),
  ];
  download(parts.join('\n'), `cluster-snapshot_${nowIso()}.csv`, 'text/csv');
}
