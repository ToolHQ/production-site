import type { ComponentChildren } from 'preact';
import { useState, useRef, useCallback } from 'preact/hooks';
import type { LiveOverview, NodeMetrics, NodeStat } from '../types/api';
import { MetricSparkline } from './MetricSparkline';

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
// TooltipWrapper — fixed-position hover card (immune to overflow clipping)
// ────────────────────────────────────────────────────────────

interface TooltipWrapperProps {
  trigger: ComponentChildren;
  card: ComponentChildren;
}

function TooltipWrapper({ trigger, card }: TooltipWrapperProps) {
  const [pos, setPos] = useState<{ top: number; left: number } | null>(null);
  const ref = useRef<HTMLDivElement>(null);

  const show = useCallback(() => {
    if (!ref.current) return;
    const r = ref.current.getBoundingClientRect();
    setPos({ top: r.bottom + 8, left: r.left + r.width / 2 });
  }, []);

  const hide = useCallback(() => setPos(null), []);

  return (
    <div ref={ref} class="node-cell-tooltip-container" onMouseEnter={show} onMouseLeave={hide}>
      {trigger}
      {pos !== null && (
        <div
          class="node-cell-tooltip-card"
          style={`position:fixed;top:${pos.top}px;left:${pos.left}px;transform:translateX(-50%);display:block;`}
        >
          {card}
        </div>
      )}
    </div>
  );
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
  history?: {
    cpu: { timestamp: number; value: number }[];
    mem: { timestamp: number; value: number }[];
    disk: { timestamp: number; value: number }[];
  };
}

function NodeRow({ node, metrics, history }: NodeRowProps) {
  const readyDot = node.ready ? '🟢' : '🔴';
  const diskIcon = node.disk_pressure ? (
    <span class="node-alert node-alert--disk" title="DiskPressure ativo">💾 DiskPressure</span>
  ) : null;
  const memIcon = node.memory_pressure ? (
    <span class="node-alert node-alert--mem" title="MemoryPressure ativo">🧠 MemPressure</span>
  ) : null;
  // Pre-warnings: alert before K8s formally fires DiskPressure / MemPressure
  const diskHighWarn =
    !node.disk_pressure && metrics && metrics.disk_percent >= 80 ? (
      <span
        class="node-alert node-alert--pre-warn"
        title={`Disk at ${metrics.disk_percent.toFixed(0)}% — approaching DiskPressure threshold`}
      >
        ⚠️ Disk {metrics.disk_percent.toFixed(0)}%
      </span>
    ) : null;
  const memHighWarn =
    !node.memory_pressure && metrics && metrics.mem_percent >= 85 ? (
      <span
        class="node-alert node-alert--pre-warn"
        title={`Memory at ${metrics.mem_percent.toFixed(0)}% — approaching MemoryPressure threshold`}
      >
        ⚠️ Mem {metrics.mem_percent.toFixed(0)}%
      </span>
    ) : null;

  const roleBadge =
    node.role === 'control-plane' ? (
      <span class="node-role node-role--cp">control-plane</span>
    ) : (
      <span class="node-role node-role--worker">worker</span>
    );

  // 1. CPU cell with interactive tooltip card & sparkline
  const cpuCell = metrics ? (
    <TooltipWrapper
      trigger={
        <MiniBar
          percent={metrics.cpu_percent}
          label={`${metrics.cpu_percent.toFixed(0)}%`}
          sub={`${(metrics.cpu_percent / 100).toFixed(2)} vCPU used`}
        />
      }
      card={
        <>
          <div class="tooltip-title">{node.name} · CPU</div>
          <div class="tooltip-stat">
            <span class="tooltip-val">{metrics.cpu_percent.toFixed(1)}%</span>
            <span class="tooltip-label">utilization</span>
          </div>
          <div class="tooltip-detail">
            <strong>Absolute Value:</strong>
            <span>{fmtCpu((metrics.cpu_percent / 100) * node.cpu_millicores)} used of {fmtCpu(node.cpu_millicores)} allocated</span>
          </div>
          {history && history.cpu.length >= 1 && (
            <div class="tooltip-history">
              <div class="tooltip-history-title">Recent History (5m window)</div>
              <div class="tooltip-history-chart">
                <MetricSparkline points={history.cpu} color="#4c9be8" width={180} height={40} />
              </div>
            </div>
          )}
        </>
      }
    />
  ) : (
    <TooltipWrapper
      trigger={<span class="node-metric-alloc">{fmtCpu(node.cpu_millicores)}</span>}
      card={
        <>
          <div class="tooltip-title">{node.name} · CPU (Allocated)</div>
          <div class="tooltip-detail">
            <strong>Capacity:</strong>
            <span>{fmtCpu(node.cpu_millicores)} allocated</span>
          </div>
          <div class="tooltip-note">
            Excluded from host-level Prometheus metrics to prioritize resource conservation.
          </div>
        </>
      }
    />
  );

  // 2. Memory cell with interactive tooltip card & sparkline
  const memCell = metrics ? (
    <TooltipWrapper
      trigger={
        <MiniBar
          percent={metrics.mem_percent}
          label={`${metrics.mem_percent.toFixed(0)}%`}
          sub={`${fmtGiB(metrics.mem_used_bytes)} / ${fmtGiB(metrics.mem_total_bytes)}`}
        />
      }
      card={
        <>
          <div class="tooltip-title">{node.name} · Memory</div>
          <div class="tooltip-stat">
            <span class="tooltip-val">{metrics.mem_percent.toFixed(1)}%</span>
            <span class="tooltip-label">utilization</span>
          </div>
          <div class="tooltip-detail">
            <strong>Absolute Value:</strong>
            <span>{fmtGiB(metrics.mem_used_bytes)} used of {fmtGiB(metrics.mem_total_bytes)} total</span>
          </div>
          {history && history.mem.length >= 1 && (
            <div class="tooltip-history">
              <div class="tooltip-history-title">Recent History (5m window)</div>
              <div class="tooltip-history-chart">
                <MetricSparkline points={history.mem} color="#2ecc71" width={180} height={40} />
              </div>
            </div>
          )}
        </>
      }
    />
  ) : (
    <TooltipWrapper
      trigger={<span class="node-metric-alloc">{fmtGiB(node.memory_bytes)}</span>}
      card={
        <>
          <div class="tooltip-title">{node.name} · Memory (Allocated)</div>
          <div class="tooltip-detail">
            <strong>Capacity:</strong>
            <span>{fmtGiB(node.memory_bytes)} allocated</span>
          </div>
          <div class="tooltip-note">
            Excluded from host-level Prometheus metrics to prioritize resource conservation.
          </div>
        </>
      }
    />
  );

  // 3. Disk cell with interactive tooltip card & sparkline
  const diskCell = metrics ? (
    <TooltipWrapper
      trigger={
        <MiniBar
          percent={metrics.disk_percent}
          label={`${metrics.disk_percent.toFixed(0)}%`}
          sub={`${fmtGiB(metrics.disk_used_bytes)} / ${fmtGiB(metrics.disk_total_bytes)}`}
        />
      }
      card={
        <>
          <div class="tooltip-title">{node.name} · Disk</div>
          <div class="tooltip-stat">
            <span class="tooltip-val">{metrics.disk_percent.toFixed(1)}%</span>
            <span class="tooltip-label">utilization</span>
          </div>
          <div class="tooltip-detail">
            <strong>Absolute Value:</strong>
            <span>{fmtGiB(metrics.disk_used_bytes)} used of {fmtGiB(metrics.disk_total_bytes)} total</span>
          </div>
          {history && history.disk.length >= 1 && (
            <div class="tooltip-history">
              <div class="tooltip-history-title">Recent History (5m window)</div>
              <div class="tooltip-history-chart">
                <MetricSparkline points={history.disk} color="#e67e22" width={180} height={40} />
              </div>
            </div>
          )}
        </>
      }
    />
  ) : (
    <TooltipWrapper
      trigger={<span class="node-metric-alloc">{fmtGiB(node.ephemeral_storage_bytes)}</span>}
      card={
        <>
          <div class="tooltip-title">{node.name} · Disk (Allocated)</div>
          <div class="tooltip-detail">
            <strong>Capacity:</strong>
            <span>{fmtGiB(node.ephemeral_storage_bytes)} allocated</span>
          </div>
          <div class="tooltip-note">
            Excluded from host-level Prometheus metrics to prioritize resource conservation.
          </div>
        </>
      }
    />
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
        {diskHighWarn}
        {memHighWarn}
        {!diskIcon && !memIcon && !diskHighWarn && !memHighWarn && <span class="node-ok">—</span>}
      </td>
    </tr>
  );
}

// ────────────────────────────────────────────────────────────
// NodesPanel (export)
// ────────────────────────────────────────────────────────────

interface NodesPanelProps {
  live: LiveOverview | null;
  history?: Record<
    string,
    {
      cpu: { timestamp: number; value: number }[];
      mem: { timestamp: number; value: number }[];
      disk: { timestamp: number; value: number }[];
    }
  >;
}

export function NodesPanel({ live, history }: NodesPanelProps) {
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

      <div class="table-shell">
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
              <NodeRow
                key={node.name}
                node={node}
                metrics={nodeMetrics[node.name]}
                history={history?.[node.name]}
              />
            ))}
          </tbody>
        </table>
      </div>
      <p class="nodes-table-footnote">
        {hasRealMetrics
          ? 'Real host utilization via Prometheus node_exporter · Hover metrics to see details and sparkline.'
          : 'Allocatable capacity · not current host utilization'}
      </p>
    </div>
  );
}
