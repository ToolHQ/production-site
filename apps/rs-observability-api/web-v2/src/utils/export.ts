import type { LiveOverview, MetricsData } from '../types/api';

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

// ── Build flat snapshot object ────────────────────────────────
function buildSnapshot(live: LiveOverview | null, metrics: MetricsData | null) {
  const ts = nowIso();
  return {
    exported_at: ts,
    cluster: {
      nodes: (live?.nodes ?? []).map((n) => {
        const m = live?.node_metrics?.[n.name];
        return {
          name: n.name,
          role: n.role,
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
    'name', 'role', 'ready', 'disk_pressure', 'memory_pressure',
    'cpu_percent', 'mem_percent', 'disk_percent',
    'cpu_millicores', 'mem_total_gib', 'disk_total_gib',
  ];
  const rows = (live?.nodes ?? []).map((n) => {
    const m = live?.node_metrics?.[n.name];
    return [
      n.name,
      n.role,
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
export function exportJSON(live: LiveOverview | null, metrics: MetricsData | null): void {
  const snapshot = buildSnapshot(live, metrics);
  const json = JSON.stringify(snapshot, null, 2);
  download(json, `cluster-snapshot_${nowIso()}.json`, 'application/json');
}

export function exportCSVBundle(live: LiveOverview | null, metrics: MetricsData | null): void {
  // Single CSV: three sections separated by blank lines + section headers
  const parts = [
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
