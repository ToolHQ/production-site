import type { LiveOverview, NodeStat } from '../types/api';

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
// NodeRow (átomo)
// ────────────────────────────────────────────────────────────

interface NodeRowProps {
  node: NodeStat;
}

function NodeRow({ node }: NodeRowProps) {
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

  return (
    <tr class={`node-row${!node.ready ? ' node-row--notready' : ''}${node.disk_pressure ? ' node-row--disk' : ''}`}>
      <td class="node-name">
        <span class="node-ready-dot">{readyDot}</span>
        <span class="node-hostname">{node.name}</span>
      </td>
      <td class="node-role-cell">{roleBadge}</td>
      <td class="node-cpu">{fmtCpu(node.cpu_millicores)}</td>
      <td class="node-mem">{fmtGiB(node.memory_bytes)}</td>
      <td class="node-disk">{fmtGiB(node.ephemeral_storage_bytes)}</td>
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
        <thead>
          <tr>
            <th>Node</th>
            <th>Role</th>
            <th>CPU (alloc.)</th>
            <th>Memory (alloc.)</th>
            <th>Ephemeral</th>
            <th>Alerts</th>
          </tr>
        </thead>
        <tbody>
          {nodes.map((node) => (
            <NodeRow key={node.name} node={node} />
          ))}
        </tbody>
      </table>
    </div>
  );
}
