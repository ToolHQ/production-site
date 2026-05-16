import type { LiveOverview, NodeMetrics, NodeStat } from '../types/api';

// ────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────

function fmtGiB(bytes: number): string {
  if (bytes === 0) return '—';
  const gib = bytes / (1024 * 1024 * 1024);
  return gib >= 1 ? `${gib.toFixed(1)} GiB` : `${(bytes / (1024 * 1024)).toFixed(0)} MiB`;
}

function fmtCpu(millicores: number): string {
  if (millicores === 0) return '—';
  return millicores >= 1000
    ? `${(millicores / 1000).toFixed(2)} vCPU`
    : `${millicores}m`;
}

// ────────────────────────────────────────────────────────────
// MiniBar — CSS progress bar
// ────────────────────────────────────────────────────────────

interface MiniBarProps {
  percent: number;
  label: string;
  sub: string;
}

function MiniBar({ percent, label, sub }: MiniBarProps) {
  const pct = Math.min(100, Math.max(0, percent));
  const cls = pct >= 85 ? 'mini-bar--critical' : pct >= 65 ? 'mini-bar--warn' : '';
  return (
    <div class={`mini-bar ${cls}`}>
      <div class="mini-bar__info">
        <span class="mini-bar__label">{label}</span>
        <span class="mini-bar__sub">{sub}</span>
      </div>
      <div class="mini-bar__track">
        <div class="mini-bar__fill" style={`width:${pct}%`} />
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// NodeRow (átomo)
// ────────────────────────────────────────────────────────────

interface NodeRowProps {
  node: NodeStat;
  metrics?: NodeMetrics;
}

function NodeRow({ node, metrics }: NodeRowProps) {
  const readyDot = node.ready ? '🟢' : '🔴';
  const diskIcon = node.disk_pressure ? (
    <span class="node-alert node-alert--disk" title="DiskPressure ativo">💾 DiskPressure</span>
  ) : null;
  const memIcon = node.memory_pressure ? (
    <span class="node-alert node-alert--mem" title="MemoryPressure ativo">🧠 MemPressure</span>
  ) : null;

  const roleBadge =
    node.role === 'control-plane' ? (
      <span class="node-role node-role--cp">control-plane</span>
    ) : (
      <span class="node-role node-role--worker">worker</span>
    );

  const cpuCell = metrics ? (
    <MiniBar
      percent={metrics.cpu_percent}
      label={`${metrics.cpu_percent.toFixed(0)}%`}
      sub={`${(metrics.cpu_percent / 100).toFixed(2)} vCPU used`}
    />
  ) : (
    <span class="node-metric-alloc" title="Kubernetes allocatable (no real data)">{fmtCpu(node.cpu_millicores)}</span>
  );

  const memCell = metrics ? (
    <MiniBar
      percent={metrics.mem_percent}
      label={`${metrics.mem_percent.toFixed(0)}%`}
      sub={`${fmtGiB(metrics.mem_used_bytes)} / ${fmtGiB(metrics.mem_total_bytes)}`}
    />
  ) : (
    <span class="node-metric-alloc" title="Kubernetes allocatable (no real data)">{fmtGiB(node.memory_bytes)}</span>
  );

  const diskCell = metrics ? (
    <MiniBar
      percent={metrics.disk_percent}
      label={`${metrics.disk_percent.toFixed(0)}%`}
      sub={`${fmtGiB(metrics.disk_used_bytes)} / ${fmtGiB(metrics.disk_total_bytes)}`}
    />
  ) : (
    <span class="node-metric-alloc" title="Kubernetes allocatable (no real data)">{fmtGiB(node.ephemeral_storage_bytes)}</span>
  );

  return (
    <tr class={`node-row${!node.ready ? ' node-row--notready' : ''}${node.disk_pressure ? ' node-row--disk' : ''}`}>
      <td class="node-name">
        <span class="node-ready-dot">{readyDot}</span>
        <span class="node-hostname">{node.name}</span>
      </td>
      <td class="node-role-cell">{roleBadge}</td>
      <td class="node-cpu">{cpuCell}</td>
      <td class="node-mem">{memCell}</td>
      <td class="node-disk">{diskCell}</td>
      <td class="node-alerts">
        {diskIcon}
        {memIcon}
        {!diskIcon && !memIcon && <span class="node-ok">—</span>}
      </td>
    </tr>
  );
}

// ────────────────────────────────────────────────────────────
// NodesPanel (export)
// ────────────────────────────────────────────────────────────

interface NodesPanelProps {
  live: LiveOverview | null;
}

export function NodesPanel({ live }: NodesPanelProps) {
  const nodes = live?.nodes ?? [];
  const nodeMetrics = live?.node_metrics ?? {};
  const hasRealMetrics = Object.keys(nodeMetrics).length > 0;

  if (!live?.available || nodes.length === 0) {
    return (
      <div class="nodes-empty">
        <span>Waiting for node data…</span>
      </div>
    );
  }

  const pressureCount = nodes.filter((n) => n.disk_pressure || n.memory_pressure).length;
  const notReadyCount = nodes.filter((n) => !n.ready).length;

  return (
    <div class="nodes-panel" id="nodes-panel">
      {(pressureCount > 0 || notReadyCount > 0) && (
        <div class="nodes-alert-banner">
          {notReadyCount > 0 && (
            <span class="nodes-alert-pill nodes-alert-pill--critical">
              {notReadyCount} node{notReadyCount > 1 ? 's' : ''} NotReady
            </span>
          )}
          {pressureCount > 0 && (
            <span class="nodes-alert-pill nodes-alert-pill--warning">
              {pressureCount} node{pressureCount > 1 ? 's' : ''} with pressure
            </span>
          )}
        </div>
      )}

      <table class="nodes-table">
        <colgroup>
          <col class="col-node" />
          <col class="col-role" />
          <col class="col-cpu" />
          <col class="col-mem" />
          <col class="col-disk" />
          <col class="col-alerts" />
        </colgroup>
        <thead>
          <tr>
            <th>Node</th>
            <th>Role</th>
            <th title={hasRealMetrics ? 'Real CPU utilization (5m avg)' : 'Kubernetes allocatable CPU (fixed per node)'}>CPU</th>
            <th title={hasRealMetrics ? 'Real memory utilization' : 'Kubernetes allocatable memory (fixed per node)'}>Memory</th>
            <th title={hasRealMetrics ? 'Real disk utilization on / filesystem' : 'Kubernetes allocatable ephemeral-storage (fixed per node)'}>Disk</th>
            <th>Alerts</th>
          </tr>
        </thead>
        <tbody>
          {nodes.map((node) => (
            <NodeRow key={node.name} node={node} metrics={nodeMetrics[node.name]} />
          ))}
        </tbody>
      </table>
      <p class="nodes-table-footnote">
        {hasRealMetrics
          ? 'Real host utilization via Prometheus node_exporter'
          : 'Allocatable capacity · not current host utilization'}
      </p>
    </div>
  );
}
