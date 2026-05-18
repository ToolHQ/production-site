import type { ComponentChildren } from 'preact';
import { useState, useCallback, useMemo, useEffect } from 'preact/hooks';
import type { LiveOverview, NodeMetrics, NodeStat } from '../types/api';
import { MetricSparkline } from './MetricSparkline';
import { useAlertThresholds } from '../hooks/useAlertThresholds';
import { ThresholdSettings } from './ThresholdSettings';

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
  const [coords, setCoords] = useState<{ top: number; left: number } | null>(null);
  const [targetEl, setTargetEl] = useState<HTMLElement | null>(null);
  const [lastEnterTime, setLastEnterTime] = useState<number>(0);

  const updateCoords = useCallback((el: HTMLElement) => {
    const rect = el.getBoundingClientRect();
    setCoords({
      left: rect.left + rect.width / 2,
      top: rect.bottom + 8,
    });
  }, []);

  const handleMouseEnter = (e: MouseEvent) => {
    const el = e.currentTarget as HTMLElement;
    setTargetEl(el);
    updateCoords(el);
    setLastEnterTime(Date.now());
  };

  const handleMouseLeave = () => {
    setTargetEl(null);
    setCoords(null);
  };

  const handleToggleClick = (e: MouseEvent) => {
    const el = e.currentTarget as HTMLElement;
    // Prevent immediate closing on desktop click when triggered by mouseenter
    if (Date.now() - lastEnterTime < 300) {
      return;
    }
    if (targetEl) {
      setTargetEl(null);
      setCoords(null);
    } else {
      setTargetEl(el);
      updateCoords(el);
    }
  };

  useEffect(() => {
    if (!targetEl) return;

    const handleScrollOrResize = () => {
      updateCoords(targetEl);
    };

    // Use capture phase to catch scroll events on any scrollable parent container
    window.addEventListener('scroll', handleScrollOrResize, true);
    window.addEventListener('resize', handleScrollOrResize, true);

    return () => {
      window.removeEventListener('scroll', handleScrollOrResize, true);
      window.removeEventListener('resize', handleScrollOrResize, true);
    };
  }, [targetEl, updateCoords]);

  return (
    <div
      class="node-cell-tooltip-container"
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
      onClick={handleToggleClick}
    >
      {trigger}
      {coords && (
        <div
          class="node-cell-tooltip-card"
          style={`position: fixed; bottom: auto; top: ${coords.top}px; left: ${coords.left}px; transform: translateX(-50%); display: block;`}
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
  diskWarn?: number;
  diskCrit?: number;
  memWarn?: number;
  memCrit?: number;
  cpuWarn?: number;
  cpuCrit?: number;
  _highlight?: (text: string, query: string) => ComponentChildren;
  _query?: string;
}

function NodeRow({ node, metrics, history, diskWarn = 80, diskCrit = 90, memWarn = 85, memCrit = 92, cpuWarn = 70, cpuCrit = 90, _highlight, _query = '' }: NodeRowProps) {
  const readyDot = node.ready ? '🟢' : '🔴';
  const diskIcon = node.disk_pressure ? (
    <span class="node-alert node-alert--disk" title="DiskPressure ativo">💾 DiskPressure</span>
  ) : null;
  const memIcon = node.memory_pressure ? (
    <span class="node-alert node-alert--mem" title="MemoryPressure ativo">🧠 MemPressure</span>
  ) : null;
  // Pre-warnings: alert before K8s formally fires DiskPressure / MemPressure
  const diskHighWarn =
    !node.disk_pressure && metrics && metrics.disk_percent >= diskWarn ? (
      <span
        class={`node-alert node-alert--pre-warn${metrics.disk_percent >= diskCrit ? ' node-alert--pre-crit' : ''}`}
        title={`Disk at ${metrics.disk_percent.toFixed(0)}% — ${metrics.disk_percent >= diskCrit ? 'critical' : 'approaching DiskPressure threshold'} (warn ≥ ${diskWarn}%)`}
      >
        {metrics.disk_percent >= diskCrit ? '🔴' : '⚠️'} Disk {metrics.disk_percent.toFixed(0)}%
      </span>
    ) : null;
  const memHighWarn =
    !node.memory_pressure && metrics && metrics.mem_percent >= memWarn ? (
      <span
        class={`node-alert node-alert--pre-warn${metrics.mem_percent >= memCrit ? ' node-alert--pre-crit' : ''}`}
        title={`Memory at ${metrics.mem_percent.toFixed(0)}% — ${metrics.mem_percent >= memCrit ? 'critical' : 'approaching MemoryPressure threshold'} (warn ≥ ${memWarn}%)`}
      >
        {metrics.mem_percent >= memCrit ? '🔴' : '⚠️'} Mem {metrics.mem_percent.toFixed(0)}%
      </span>
    ) : null;
  const cpuHighWarn =
    metrics && metrics.cpu_percent >= cpuWarn ? (
      <span
        class={`node-alert node-alert--pre-warn${metrics.cpu_percent >= cpuCrit ? ' node-alert--pre-crit' : ''}`}
        title={`CPU at ${metrics.cpu_percent.toFixed(0)}% — ${metrics.cpu_percent >= cpuCrit ? 'critical' : 'high utilization'} (warn ≥ ${cpuWarn}%)`}
      >
        {metrics.cpu_percent >= cpuCrit ? '🔴' : '⚠️'} CPU {metrics.cpu_percent.toFixed(0)}%
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
            <strong>Físico (Host):</strong>
            <span>{((metrics.cpu_percent / 100) * 1.0).toFixed(2)} vCPU usado de 1.00 vCPU</span>
          </div>
          <div class="tooltip-detail">
            <strong>Kubernetes (Alocável):</strong>
            <span>{fmtCpu(node.cpu_millicores)} reservado no cluster</span>
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
            <strong>Físico (Host):</strong>
            <span>{fmtGiB(metrics.mem_used_bytes)} usado de {fmtGiB(metrics.mem_total_bytes)} total</span>
          </div>
          <div class="tooltip-detail">
            <strong>Kubernetes (Alocável):</strong>
            <span>{fmtGiB(node.memory_bytes)} reservado no cluster</span>
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
            <strong>Físico (Host):</strong>
            <span>{fmtGiB(metrics.disk_used_bytes)} usado de {fmtGiB(metrics.disk_total_bytes)} total</span>
          </div>
          <div class="tooltip-detail">
            <strong>Kubernetes (Alocável):</strong>
            <span>{fmtGiB(node.ephemeral_storage_bytes)} reservado no cluster</span>
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
        <span class="node-hostname">{_highlight ? _highlight(node.name, _query) : node.name}</span>
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
        {cpuHighWarn}
        {!diskIcon && !memIcon && !diskHighWarn && !memHighWarn && !cpuHighWarn && <span class="node-ok">—</span>}
      </td>
    </tr>
  );
}

// ────────────────────────────────────────────────────────────
// NodeCard — mobile card view (< 768px, CSS shows this)
// ────────────────────────────────────────────────────────────

interface NodeCardProps {
  node: NodeStat;
  metrics?: NodeMetrics;
  diskWarn: number;
  diskCrit: number;
  memWarn: number;
  memCrit: number;
  cpuWarn: number;
  cpuCrit: number;
  highlight?: (text: string, query: string) => ComponentChildren;
  query?: string;
}

function NodeCard({ node, metrics, diskWarn, diskCrit, memWarn, memCrit, cpuWarn, cpuCrit, highlight, query = '' }: NodeCardProps) {
  const pct = (v: number, warn: number, crit: number) =>
    v >= crit ? 'crit' : v >= warn ? 'warn' : 'ok';
  const bar = (v: number | undefined, warn: number, crit: number) => {
    if (v === undefined) return null;
    const level = pct(v, warn, crit);
    return (
      <div class="nc-bar-track">
        <div
          class={`nc-bar-fill nc-bar-fill--${level}`}
          style={{ width: `${Math.min(v, 100)}%` }}
        />
        <span class="nc-bar-label">{v.toFixed(0)}%</span>
      </div>
    );
  };

  const alerts = [];
  if (node.disk_pressure) alerts.push(<span class="node-alert node-alert--disk">💾 DiskPressure</span>);
  if (node.memory_pressure) alerts.push(<span class="node-alert node-alert--mem">🧠 MemPressure</span>);
  if (!node.disk_pressure && metrics && metrics.disk_percent >= diskWarn)
    alerts.push(<span class={`node-alert node-alert--pre-warn${metrics.disk_percent >= diskCrit ? ' node-alert--pre-crit' : ''}`}>
      {metrics.disk_percent >= diskCrit ? '🔴' : '⚠️'} Disk {metrics.disk_percent.toFixed(0)}%
    </span>);
  if (!node.memory_pressure && metrics && metrics.mem_percent >= memWarn)
    alerts.push(<span class={`node-alert node-alert--pre-warn${metrics.mem_percent >= memCrit ? ' node-alert--pre-crit' : ''}`}>
      {metrics.mem_percent >= memCrit ? '🔴' : '⚠️'} Mem {metrics.mem_percent.toFixed(0)}%
    </span>);
  if (metrics && metrics.cpu_percent >= cpuWarn)
    alerts.push(<span class={`node-alert node-alert--pre-warn${metrics.cpu_percent >= cpuCrit ? ' node-alert--pre-crit' : ''}`}>
      {metrics.cpu_percent >= cpuCrit ? '🔴' : '⚠️'} CPU {metrics.cpu_percent.toFixed(0)}%
    </span>);

  return (
    <div class={`node-card${!node.ready ? ' node-card--notready' : ''}${node.disk_pressure ? ' node-card--disk' : ''}`}>
      <div class="nc-header">
        <span class="node-ready-dot">{node.ready ? '🟢' : '🔴'}</span>
        <span class="nc-name">{highlight ? highlight(node.name, query) : node.name}</span>
        <span class={`node-role node-role--${node.role === 'control-plane' ? 'cp' : 'worker'}`}>{node.role}</span>
      </div>
      {metrics ? (
        <div class="nc-metrics">
          <div class="nc-metric-row">
            <span class="nc-metric-lbl">CPU</span>
            {bar(metrics.cpu_percent, cpuWarn, cpuCrit)}
          </div>
          <div class="nc-metric-row">
            <span class="nc-metric-lbl">Mem</span>
            {bar(metrics.mem_percent, memWarn, memCrit)}
          </div>
          <div class="nc-metric-row">
            <span class="nc-metric-lbl">Disk</span>
            {bar(metrics.disk_percent, diskWarn, diskCrit)}
          </div>
        </div>
      ) : (
        <div class="nc-no-metrics">No Prometheus metrics</div>
      )}
      {alerts.length > 0 && <div class="nc-alerts">{alerts}</div>}
    </div>
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

  const [search, setSearch] = useState('');
  const [showSettings, setShowSettings] = useState(false);
  const { thresholds, update: updateThreshold, reset: resetThresholds } = useAlertThresholds();

  const filteredNodes = useMemo(() => {
    if (!search.trim()) return nodes;
    const q = search.toLowerCase();
    return nodes.filter((n) =>
      n.name.toLowerCase().includes(q) ||
      n.role.toLowerCase().includes(q) ||
      (n.ready ? 'ready' : 'notready').includes(q)
    );
  }, [nodes, search]);

  const highlightText = useCallback((text: string, query: string): ComponentChildren => {
    if (!query.trim()) return text;
    const idx = text.toLowerCase().indexOf(query.toLowerCase());
    if (idx === -1) return text;
    return (
      <>
        {text.slice(0, idx)}
        <mark class="search-highlight">{text.slice(idx, idx + query.length)}</mark>
        {text.slice(idx + query.length)}
      </>
    );
  }, []);

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
      {/* ── Search + Settings bar ── */}
      <div class="nodes-toolbar">
        <div class="nodes-search-wrapper">
          <span class="nodes-search-icon">⌕</span>
          <input
            type="search"
            class="nodes-search"
            placeholder="Filter nodes…"
            value={search}
            onInput={(e) => setSearch(e.currentTarget.value)}
            aria-label="Filter nodes by name or role"
          />
          {search && (
            <button class="nodes-search-clear" onClick={() => setSearch('')} aria-label="Clear search">✕</button>
          )}
        </div>
        <button
          class="nodes-settings-btn"
          onClick={() => setShowSettings(true)}
          title="Configure alert thresholds"
          aria-label="Configure alert thresholds"
        >
          ⚙ Thresholds
        </button>
      </div>

      {/* ── Threshold Settings Modal ── */}
      {showSettings && (
        <ThresholdSettings
          thresholds={thresholds}
          onUpdate={updateThreshold}
          onReset={resetThresholds}
          onClose={() => setShowSettings(false)}
        />
      )}

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

      {filteredNodes.length === 0 && search && (
        <div class="nodes-empty">No nodes match &quot;<strong>{search}</strong>&quot;</div>
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
              <th>Node{search && filteredNodes.length < nodes.length && <span class="nodes-search-count"> {filteredNodes.length}/{nodes.length}</span>}</th>
              <th>Role</th>
              <th title={hasRealMetrics ? 'Real CPU utilization (5m avg)' : 'Kubernetes allocatable CPU (fixed per node)'}>CPU</th>
              <th title={hasRealMetrics ? 'Real memory utilization' : 'Kubernetes allocatable memory (fixed per node)'}>Memory</th>
              <th title={hasRealMetrics ? 'Real disk utilization on / filesystem' : 'Kubernetes allocatable ephemeral-storage (fixed per node)'}>Disk</th>
              <th>Alerts</th>
            </tr>
          </thead>
          <tbody>
            {filteredNodes.map((node) => (
              <NodeRow
                key={node.name}
                node={{ ...node, name: node.name }}
                metrics={nodeMetrics[node.name]}
                history={history?.[node.name]}
                diskWarn={thresholds.disk_warn}
                diskCrit={thresholds.disk_crit}
                memWarn={thresholds.mem_warn}
                memCrit={thresholds.mem_crit}
                cpuWarn={thresholds.cpu_warn}
                cpuCrit={thresholds.cpu_crit}
                _highlight={highlightText}
                _query={search}
              />
            ))}
          </tbody>
        </table>
      </div>

      {/* ── Mobile card view (CSS shows/hides based on viewport) ── */}
      <div class="node-cards-mobile">
        {filteredNodes.map((node) => (
          <NodeCard
            key={node.name}
            node={node}
            metrics={nodeMetrics[node.name]}
            diskWarn={thresholds.disk_warn}
            diskCrit={thresholds.disk_crit}
            memWarn={thresholds.mem_warn}
            memCrit={thresholds.mem_crit}
            cpuWarn={thresholds.cpu_warn}
            cpuCrit={thresholds.cpu_crit}
            highlight={highlightText}
            query={search}
          />
        ))}
      </div>
      <p class="nodes-table-footnote">
        {hasRealMetrics
          ? 'Real host utilization via Prometheus node_exporter · Hover metrics to see details and sparkline.'
          : 'Allocatable capacity · not current host utilization'}
      </p>
    </div>
  );
}
