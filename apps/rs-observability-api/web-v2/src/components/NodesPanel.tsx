import type { ComponentChildren } from 'preact';
import { useState, useCallback, useMemo, useEffect } from 'preact/hooks';
import { createPortal } from 'preact/compat';
import type { LiveOverview, NodeMetrics, NodeStat, HoneypotNodeStats } from '../types/api';
import { MetricSparkline } from './MetricSparkline';
import { useAlertThresholds } from '../hooks/useAlertThresholds';
import { ThresholdSettings } from './ThresholdSettings';
import { clusterBadgeClass, clusterBadgeSlug } from '../utils/clusterBadge';
import { FleetOverviewTable } from './FleetOverviewTable';
import { FleetCopilotTeaser } from './FleetCopilotTeaser';
import { buildFleetOverviewRows, filterFleetRows, honeypotActivityMetrics, type FleetPeriod } from '../utils/fleetOverview';
import { useDnorShell } from '../context/DnorShellContext';

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

/** Ensures only one hover tooltip is open — scroll skips mouseleave between rows. */
let activeHoverTooltipClose: (() => void) | null = null;

function dismissActiveHoverTooltip() {
  activeHoverTooltipClose?.();
  activeHoverTooltipClose = null;
}

function TooltipWrapper({ trigger, card }: TooltipWrapperProps) {
  const [coords, setCoords] = useState<{ top: number; left: number } | null>(null);
  const [targetEl, setTargetEl] = useState<HTMLElement | null>(null);
  const [lastEnterTime, setLastEnterTime] = useState<number>(0);
  const [isPinned, setIsPinned] = useState<boolean>(false);

  const closeTooltip = useCallback(() => {
    setTargetEl(null);
    setCoords(null);
  }, []);

  const updateCoords = useCallback((el: HTMLElement) => {
    const rect = el.getBoundingClientRect();
    setCoords({
      left: rect.left + rect.width / 2,
      top: rect.bottom + 8,
    });
  }, []);

  const handleMouseEnter = (e: MouseEvent) => {
    if (isPinned) return;
    dismissActiveHoverTooltip();
    const el = e.currentTarget as HTMLElement;
    setTargetEl(el);
    updateCoords(el);
    setLastEnterTime(Date.now());
    activeHoverTooltipClose = () => {
      closeTooltip();
    };
  };

  const handleMouseLeave = () => {
    if (isPinned) return;
    activeHoverTooltipClose = null;
    closeTooltip();
  };

  const handleToggleClick = (e: MouseEvent) => {
    e.stopPropagation();
    const el = e.currentTarget as HTMLElement;
    // Prevent immediate closing on desktop click when triggered by mouseenter
    if (Date.now() - lastEnterTime < 300) {
      return;
    }
    if (isPinned) {
      setIsPinned(false);
      activeHoverTooltipClose = null;
      closeTooltip();
    } else {
      dismissActiveHoverTooltip();
      setIsPinned(true);
      setTargetEl(el);
      updateCoords(el);
    }
  };

  useEffect(() => {
    if (!targetEl) return;

    const handleScrollOrResize = () => {
      if (isPinned) {
        updateCoords(targetEl);
        return;
      }
      // Wheel/scroll moves rows under the cursor without mouseleave.
      dismissActiveHoverTooltip();
    };

    // Use capture phase to catch scroll events on any scrollable parent container
    window.addEventListener('scroll', handleScrollOrResize, true);
    window.addEventListener('resize', handleScrollOrResize, true);
    window.addEventListener('wheel', handleScrollOrResize, { capture: true, passive: true });

    return () => {
      window.removeEventListener('scroll', handleScrollOrResize, true);
      window.removeEventListener('resize', handleScrollOrResize, true);
      window.removeEventListener('wheel', handleScrollOrResize, true);
    };
  }, [targetEl, updateCoords, isPinned]);

  useEffect(() => {
    return () => {
      if (activeHoverTooltipClose) {
        activeHoverTooltipClose = null;
      }
    };
  }, []);

  useEffect(() => {
    if (!isPinned || !targetEl) return;

    const handleClickOutside = (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      // Don't close if clicking the trigger container itself
      if (targetEl.contains(target)) {
        return;
      }
      // Since the card is rendered in a Portal, find it in the DOM
      const cardEl = document.querySelector('.node-cell-tooltip-card');
      if (cardEl && cardEl.contains(target)) {
        return;
      }

      setIsPinned(false);
      activeHoverTooltipClose = null;
      closeTooltip();
    };

    document.addEventListener('click', handleClickOutside, true);
    return () => {
      document.removeEventListener('click', handleClickOutside, true);
    };
  }, [isPinned, targetEl, closeTooltip]);

  return (
    <div
      class="node-cell-tooltip-container"
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
      onClick={handleToggleClick}
    >
      {trigger}
      {coords && createPortal(
        <div
          class="node-cell-tooltip-card"
          style={`position: fixed; bottom: auto; top: ${coords.top}px; left: ${coords.left}px; transform: translateX(-50%); display: block; pointer-events: ${isPinned ? 'auto' : 'none'};`}
        >
          {card}
        </div>,
        document.body
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
    ) : node.role === 'builder' ? (
      <span class="node-role node-role--builder">builder</span>
    ) : node.role === 'dedicated' ? (
      <span class="node-role node-role--dedicated">dedicated</span>
    ) : (
      <span class="node-role node-role--worker">worker</span>
    );

  const clusterBadge = (
    <span class={`node-cluster-badge ${clusterBadgeClass(node.cluster)}`}>{node.cluster}</span>
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
      <td class="node-cluster-cell">{clusterBadge}</td>
      <td class="node-role-cell">{roleBadge}</td>
      <td class="node-ip-cell">{_highlight ? _highlight(node.ip, _query) : node.ip}</td>
      <td class="node-arch-cell">{_highlight ? _highlight(node.architecture, _query) : node.architecture}</td>
      <td class="node-os-cell" title={node.operating_system}>
        {_highlight ? _highlight(node.operating_system, _query) : node.operating_system}
      </td>
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
        <span class={`node-cluster-badge ${clusterBadgeClass(node.cluster)}`}>{node.cluster}</span>
        <span class={`node-role node-role--${node.role === 'control-plane' ? 'cp' : node.role === 'builder' ? 'builder' : node.role === 'dedicated' ? 'dedicated' : 'worker'}`}>{node.role}</span>
      </div>
      <div class="nc-meta">
        <span class="nc-meta-pill">IP: {node.ip}</span>
        <span class="nc-meta-pill">Arch: {node.architecture}</span>
        <span class="nc-meta-pill" title={node.operating_system}>OS: {node.operating_system}</span>
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
// HoneypotHeroCard — featured honeypot node (qdbback / external fleet)
// ────────────────────────────────────────────────────────────

function HoneypotRadarIcon() {
  return (
    <div class="honeypot-hero__radar" aria-hidden="true">
      <svg viewBox="0 0 120 120" class="honeypot-hero__radar-svg">
        <circle cx="60" cy="60" r="52" class="honeypot-hero__ring honeypot-hero__ring--3" />
        <circle cx="60" cy="60" r="38" class="honeypot-hero__ring honeypot-hero__ring--2" />
        <circle cx="60" cy="60" r="24" class="honeypot-hero__ring honeypot-hero__ring--1" />
        <line x1="60" y1="8" x2="60" y2="112" class="honeypot-hero__cross" />
        <line x1="8" y1="60" x2="112" y2="60" class="honeypot-hero__cross" />
        <path
          class="honeypot-hero__sweep"
          d="M60 60 L60 12 A48 48 0 0 1 96 36 Z"
        />
        <circle cx="60" cy="60" r="18" class="honeypot-hero__pot-base" />
        <ellipse cx="60" cy="48" rx="14" ry="6" class="honeypot-hero__pot-rim" />
        <path
          class="honeypot-hero__pot-body"
          d="M46 48 C46 58 48 68 60 72 C72 68 74 58 74 48 Z"
        />
        <text x="60" y="54" text-anchor="middle" class="honeypot-hero__pot-icon">
          🍯
        </text>
      </svg>
    </div>
  );
}

function HoneypotBarSparkline({ seed, color = '#ff9900' }: { seed: number; color?: string }) {
  const bars = 14;
  const heights = useMemo(() => {
    return Array.from({ length: bars }, (_, i) => {
      const wave = Math.sin(seed * 0.0007 + i * 0.95) * 0.35 + Math.cos(i * 0.55) * 0.25;
      return Math.max(12, Math.min(100, 38 + wave * 42 + (i % 3) * 8));
    });
  }, [seed]);

  return (
    <svg class="honeypot-hero__bars" viewBox="0 0 140 28" preserveAspectRatio="none" aria-hidden="true">
      {heights.map((h, i) => (
        <rect
          key={i}
          x={i * 10 + 1}
          y={28 - (h / 100) * 24}
          width="7"
          height={(h / 100) * 24}
          rx="1.5"
          fill={color}
          opacity={0.35 + (i / bars) * 0.45}
        />
      ))}
    </svg>
  );
}

function CopyHostButton({ value }: { value: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = useCallback(async (e: MouseEvent) => {
    e.stopPropagation();
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1800);
    } catch {
      /* clipboard unavailable */
    }
  }, [value]);

  return (
    <button
      type="button"
      class="honeypot-hero__copy"
      onClick={handleCopy}
      title="Copy IP address"
      aria-label={copied ? 'Copied' : `Copy ${value}`}
    >
      {copied ? '✓' : '⎘'}
    </button>
  );
}

interface HoneypotThreatsCardProps {
  stats: HoneypotNodeStats;
  period: FleetPeriod;
}

function HoneypotThreatsCard({ stats, period }: HoneypotThreatsCardProps) {
  const topTags = stats.top_tags.slice(0, 3);
  const isClassified = stats.available && stats.classified > 0;
  const sparkSeed = stats.total + stats.last24h * 97;
  const activity = honeypotActivityMetrics(stats, period);
  const hasRealActivity = activity.series.length >= 2;
  const hasReal7d = (stats.requests_7d?.length ?? 0) >= 2;

  return (
    <article class={`honeypot-hero ${stats.available ? '' : 'honeypot-hero--error'}`}>
      <HoneypotRadarIcon />

      <div class="honeypot-hero__body">
        <div class="honeypot-hero__heading">
          <h3 class="honeypot-hero__title">
            Honeypot
            <span class="honeypot-hero__env-badge">{stats.cluster}</span>
          </h3>
          <p class="honeypot-hero__desc">
            This node is a honeypot deployed to simulate exposed services and detect malicious activity.
          </p>
        </div>
        <div class="honeypot-hero__host-row">
          <code class="honeypot-hero__host">{stats.instance_host}</code>
          <CopyHostButton value={stats.instance_host} />
        </div>
      </div>

      {stats.available ? (
        <div class="honeypot-hero__metrics">
          <div class="honeypot-hero__metric">
            <span class="honeypot-hero__metric-label">Total Requests</span>
            <span class="honeypot-hero__metric-value">{stats.total.toLocaleString()}</span>
            {hasReal7d ? (
              <MetricSparkline points={stats.requests_7d!} color="#ff9900" width={140} height={28} />
            ) : (
              <HoneypotBarSparkline seed={sparkSeed} />
            )}
          </div>
          <div class="honeypot-hero__metric">
            <span class="honeypot-hero__metric-label">{activity.label}</span>
            <span class="honeypot-hero__metric-value">{activity.value.toLocaleString()}</span>
            {hasRealActivity ? (
              <MetricSparkline points={activity.series} color="#ffb347" width={140} height={28} />
            ) : (
              <HoneypotBarSparkline seed={sparkSeed + 17} color="#ffb347" />
            )}
          </div>
          <div class="honeypot-hero__metric honeypot-hero__metric--classified">
            <span class="honeypot-hero__metric-label">Classified</span>
            <span class={`honeypot-hero__classified-badge${isClassified ? ' honeypot-hero__classified-badge--yes' : ''}`}>
              {isClassified ? 'Yes' : 'No'}
            </span>
            <span class="honeypot-hero__classified-sub">
              {isClassified ? 'Honeypot traffic' : `${stats.unclassified.toLocaleString()} unclassified`}
            </span>
          </div>
          {topTags.length > 0 && (
            <div class="honeypot-hero__metric honeypot-hero__metric--tags">
              <span class="honeypot-hero__metric-label">Tags</span>
              <div class="honeypot-hero__tag-list">
                {topTags.map((item) => (
                  <span key={item.tag} class="honeypot-hero__tag">
                    {item.tag}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      ) : (
        <p class="honeypot-hero__error">{stats.error ?? 'Honeypot metrics unavailable'}</p>
      )}

      {stats.recent_requests && stats.recent_requests.length > 0 && (
        <div class="honeypot-hero__threat-table-wrapper" style={{ marginTop: '1rem', borderTop: '1px solid rgba(255, 179, 71, 0.15)', paddingTop: '1rem', marginLeft: '5rem' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.75rem' }}>
            <h4 style={{ fontSize: '0.75rem', textTransform: 'uppercase', color: '#ffb347', letterSpacing: '0.05em', fontWeight: 600, margin: 0 }}>Recent Intercepts</h4>
            <a href="#threats" style={{ fontSize: '0.75rem', color: '#ffb347', textDecoration: 'none', border: '1px solid rgba(255, 179, 71, 0.3)', padding: '0.25rem 0.75rem', borderRadius: '4px', background: 'rgba(255, 179, 71, 0.05)', fontWeight: 500 }}>Ver Todas as Ameaças →</a>
          </div>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.85rem', textAlign: 'left' }}>
            <thead>
              <tr style={{ color: 'rgba(255, 255, 255, 0.5)', borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
                <th style={{ padding: '0.5rem 0', fontWeight: 500 }}>Time</th>
                <th style={{ padding: '0.5rem 0', fontWeight: 500 }}>IP Address</th>
                <th style={{ padding: '0.5rem 0', fontWeight: 500 }}>Method / Path</th>
                <th style={{ padding: '0.5rem 0', fontWeight: 500 }}>Tag</th>
                <th style={{ padding: '0.5rem 0', fontWeight: 500 }}>User-Agent</th>
              </tr>
            </thead>
            <tbody>
              {stats.recent_requests.map((req, idx) => (
                <tr key={`${req.ip}-${idx}`} style={{ borderBottom: '1px solid rgba(255,255,255,0.02)' }}>
                  <td style={{ padding: '0.5rem 0', color: '#94a3b8', whiteSpace: 'nowrap' }}>
                    {new Date(req.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
                  </td>
                  <td style={{ padding: '0.5rem 0', fontFamily: 'var(--font-mono)', color: '#e2e8f0' }}>{req.ip}</td>
                  <td style={{ padding: '0.5rem 0', color: '#e2e8f0' }}>
                    <span style={{ color: '#ffb347', marginRight: '0.5rem', fontSize: '0.75rem', fontWeight: 600 }}>{req.method}</span>
                    <span style={{ fontFamily: 'var(--font-mono)', color: '#94a3b8' }}>{req.path.length > 25 ? req.path.substring(0, 25) + '...' : req.path}</span>
                  </td>
                  <td style={{ padding: '0.5rem 0' }}>
                    {req.tag ? (
                      <span class="honeypot-hero__tag" style={{ background: 'rgba(255, 179, 71, 0.1)', borderColor: 'rgba(255, 179, 71, 0.2)', color: '#ffb347' }}>
                        {req.tag}
                      </span>
                    ) : (
                      <span style={{ color: '#64748b', fontSize: '0.75rem', fontStyle: 'italic' }}>none</span>
                    )}
                  </td>
                  <td style={{ padding: '0.5rem 0', color: '#64748b', fontSize: '0.75rem', maxWidth: '200px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={req.userAgent}>
                    {req.userAgent || 'Unknown'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </article>
  );
}

// ────────────────────────────────────────────────────────────
// Fail2BanCard — featured Fail2Ban stats for SSDNodes
// ────────────────────────────────────────────────────────────

function ShieldIcon() {
  return (
    <div class="honeypot-hero__radar" aria-hidden="true">
      <svg viewBox="0 0 120 120" class="honeypot-hero__radar-svg">
        <circle cx="60" cy="60" r="52" class="honeypot-hero__ring honeypot-hero__ring--3" />
        <circle cx="60" cy="60" r="38" class="honeypot-hero__ring honeypot-hero__ring--2" />
        <circle cx="60" cy="60" r="24" class="honeypot-hero__ring honeypot-hero__ring--1" />
        <line x1="60" y1="8" x2="60" y2="112" class="honeypot-hero__cross" />
        <line x1="8" y1="60" x2="112" y2="60" class="honeypot-hero__cross" />
        <path
          d="M60 20 L90 35 L90 65 C90 85 75 100 60 105 C45 100 30 85 30 65 L30 35 Z"
          fill="rgba(255, 60, 60, 0.15)"
          stroke="#ff3c3c"
          stroke-width="2"
        />
        <text x="60" y="65" text-anchor="middle" font-size="28" fill="#ff3c3c">
          🛡️
        </text>
      </svg>
    </div>
  );
}

function Fail2BanCard({ stats }: { stats: import('../types/api').Fail2BanStats }) {
  const topIps = stats.banned_ip_details?.slice(0, 5) || [];
  const sparkSeed = stats.total + stats.failed * 97;

  return (
    <article class="honeypot-hero">
      <ShieldIcon />

      <div class="honeypot-hero__body">
        <div class="honeypot-hero__heading">
          <h3 class="honeypot-hero__title">
            Fail2Ban Shield
            <span class="honeypot-hero__env-badge">SSD-NODES</span>
          </h3>
          <p class="honeypot-hero__desc">
            Local protection against brute force attacks on exposed SSH ports.
          </p>
        </div>
        <div class="honeypot-hero__host-row">
          <code class="honeypot-hero__host">104.225.218.78</code>
          <CopyHostButton value="104.225.218.78" />
        </div>
      </div>

      <div class="honeypot-hero__metrics">
        <div class="honeypot-hero__metric">
          <span class="honeypot-hero__metric-label">Total Banned</span>
          <span class="honeypot-hero__metric-value">{stats.total.toLocaleString()}</span>
          <HoneypotBarSparkline seed={sparkSeed} color="#ff3c3c" />
        </div>
        <div class="honeypot-hero__metric">
          <span class="honeypot-hero__metric-label">Currently Failed</span>
          <span class="honeypot-hero__metric-value">{stats.failed.toLocaleString()}</span>
          <HoneypotBarSparkline seed={sparkSeed + 17} color="#ff8888" />
        </div>
        <div class="honeypot-hero__metric honeypot-hero__metric--classified">
          <span class="honeypot-hero__metric-label">Status</span>
          <span class="honeypot-hero__classified-badge honeypot-hero__classified-badge--yes" style="background: rgba(255, 60, 60, 0.2); color: #ff8888; border-color: rgba(255, 60, 60, 0.3);">
            Active
          </span>
          <span class="honeypot-hero__classified-sub">
            Protecting port 22
          </span>
        </div>
      </div>

      {topIps.length > 0 && (
        <div class="honeypot-hero__threat-table-wrapper" style={{ marginTop: '1rem', borderTop: '1px solid rgba(255, 60, 60, 0.15)', paddingTop: '1rem', marginLeft: '5rem' }}>
          <h4 style={{ fontSize: '0.75rem', textTransform: 'uppercase', color: '#ff8888', marginBottom: '0.75rem', letterSpacing: '0.05em', fontWeight: 600 }}>Recent Threat Actors</h4>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.85rem', textAlign: 'left' }}>
            <thead>
              <tr style={{ color: 'rgba(255, 255, 255, 0.5)', borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
                <th style={{ padding: '0.5rem 0', fontWeight: 500 }}>IP Address</th>
                <th style={{ padding: '0.5rem 0', fontWeight: 500 }}>Hits</th>
                <th style={{ padding: '0.5rem 0', fontWeight: 500 }}>Duration</th>
                <th style={{ padding: '0.5rem 0', fontWeight: 500 }}>Status</th>
              </tr>
            </thead>
            <tbody>
              {topIps.map(ip => {
                const durationMins = Math.round(((ip.last_seen || 0) - (ip.first_seen || 0)) / 60);
                const isAggressive = (ip.hits || 0) > 10;
                const isBanned = Array.isArray(ip.statuses) && (ip.statuses.includes('banned') || ip.statuses.includes('ban'));
                return (
                  <tr key={ip.ip} style={{ borderBottom: '1px solid rgba(255,255,255,0.02)' }}>
                    <td style={{ padding: '0.5rem 0', fontFamily: 'var(--font-mono)', color: '#e2e8f0' }}>{ip.ip}</td>
                    <td style={{ padding: '0.5rem 0', color: isAggressive ? '#ff3c3c' : '#ff8888', fontWeight: isAggressive ? 600 : 400 }}>{ip.hits}</td>
                    <td style={{ padding: '0.5rem 0', color: '#94a3b8' }}>{durationMins > 0 ? `${durationMins}m` : '<1m'}</td>
                    <td style={{ padding: '0.5rem 0' }}>
                      <span class="honeypot-hero__tag" style={{ background: isBanned ? 'rgba(255, 60, 60, 0.15)' : 'rgba(255, 136, 136, 0.1)', borderColor: isBanned ? 'rgba(255, 60, 60, 0.3)' : 'rgba(255, 60, 60, 0.15)', color: isBanned ? '#ff8888' : '#e2e8f0' }}>
                        {isBanned ? 'Banned' : 'Failed'}
                      </span>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </article>
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

  const { nodeSearch, setNodeSearch, period } = useDnorShell();
  const search = nodeSearch;
  const setSearch = setNodeSearch;
  const [showSettings, setShowSettings] = useState(false);
  const [includeHoneypot, setIncludeHoneypot] = useState(true);
  const { thresholds, update: updateThreshold, reset: resetThresholds } = useAlertThresholds();

  const filteredNodes = useMemo(() => {
    if (!search.trim()) return nodes;
    const q = search.toLowerCase();
    return nodes.filter((n) =>
      n.name.toLowerCase().includes(q) ||
      n.role.toLowerCase().includes(q) ||
      n.cluster.toLowerCase().includes(q) ||
      n.ip.toLowerCase().includes(q) ||
      n.architecture.toLowerCase().includes(q) ||
      n.operating_system.toLowerCase().includes(q) ||
      (n.ready ? 'ready' : 'notready').includes(q)
    );
  }, [nodes, search]);

  // Cluster ordering: known clusters first, then alphabetical
  const CLUSTER_ORDER = ['OCI-K8S', 'SSD-NODES', 'HETZNER', 'AWS-EC2'];

  // When searching: flat list. Otherwise: group by cluster.
  const groupedNodes = useMemo(() => {
    const map = new Map<string, NodeStat[]>();
    for (const node of filteredNodes) {
      const list = map.get(node.cluster) ?? [];
      list.push(node);
      map.set(node.cluster, list);
    }
    const sorted = [...map.keys()].sort((a, b) => {
      const ai = CLUSTER_ORDER.indexOf(a);
      const bi = CLUSTER_ORDER.indexOf(b);
      if (ai === -1 && bi === -1) return a.localeCompare(b);
      if (ai === -1) return 1;
      if (bi === -1) return -1;
      return ai - bi;
    });
    return sorted.map((cluster) => ({ cluster, nodes: map.get(cluster)! }));
  }, [filteredNodes]);

  const showGroupHeaders = !search.trim() && groupedNodes.length > 1;

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

  const honeypotNodes = live?.honeypot?.nodes ?? [];
  const fleetRows = useMemo(
    () => buildFleetOverviewRows(nodes, honeypotNodes),
    [nodes, honeypotNodes],
  );
  const filteredFleetRows = useMemo(() => {
    const rows = filterFleetRows(fleetRows, search);
    if (includeHoneypot) return rows;
    return rows.filter((r) => !r.isHoneypot);
  }, [fleetRows, search, includeHoneypot]);

  if (!live?.available || nodes.length === 0) {
    return (
      <div class="nodes-empty nodes-empty--rich">
        <p class="nodes-empty__title">Aguardando dados dos nós</p>
        <p class="nodes-empty__hint">
          {live?.error
            ? live.error
            : 'O endpoint live ainda não retornou nós. Verifique tunnel kubectl, API do cluster e refresh do dashboard.'}
        </p>
        <ul class="nodes-empty__checklist">
          <li>Tunnel SSH na porta 6445 ativo</li>
          <li>Pod rs-observability-api com acesso à API K8s</li>
          <li>Prometheus/node_exporter coletando métricas</li>
        </ul>
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
            placeholder="Filtrar nós (nome, cluster, IP…)"
            value={search}
            onInput={(e) => setSearch(e.currentTarget.value)}
            aria-label="Filter nodes by name, role, cluster, IP, architecture, or OS"
          />
          {search && (
            <button class="nodes-search-clear" onClick={() => setSearch('')} aria-label="Clear search">✕</button>
          )}
        </div>
        {honeypotNodes.length > 0 && (
          <label class="nodes-honeypot-toggle">
            <input
              type="checkbox"
              checked={includeHoneypot}
              onChange={(e) => setIncludeHoneypot(e.currentTarget.checked)}
            />
            Incluir honeypot na tabela
          </label>
        )}
        <button
          class="nodes-settings-btn"
          onClick={() => setShowSettings(true)}
          title="Limites de alerta de CPU, memória e disco"
          aria-label="Limites de alerta"
        >
          ⚙ Limites
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

      {(honeypotNodes.length > 0 || live?.fail2ban) && (
        <div class="honeypot-hero-panel">
          {honeypotNodes.map((stats) => (
            <HoneypotThreatsCard key={stats.id} stats={stats} period={period} />
          ))}
          {live?.fail2ban && (
            <Fail2BanCard stats={live.fail2ban} />
          )}
        </div>
      )}

      <FleetOverviewTable
        rows={filteredFleetRows}
        period={period}
        highlight={highlightText}
        query={search}
      />

      {filteredFleetRows.length === 0 && search && (
        <div class="nodes-empty">No fleet nodes match &quot;<strong>{search}</strong>&quot;</div>
      )}

      <div class="nodes-section-divider">
        <h3 class="nodes-section-divider__title">Infrastructure metrics</h3>
        <p class="nodes-section-divider__subtitle">CPU, memory and disk utilization per node</p>
      </div>

      {filteredNodes.length === 0 && search && filteredFleetRows.length > 0 && (
        <div class="nodes-empty">No infrastructure nodes match &quot;<strong>{search}</strong>&quot;</div>
      )}

      <div class="table-shell">
        <table class="nodes-table">
          <colgroup>
            <col class="col-node" />
            <col class="col-cluster" />
            <col class="col-role" />
            <col class="col-ip" />
            <col class="col-arch" />
            <col class="col-os" />
            <col class="col-cpu" />
            <col class="col-mem" />
            <col class="col-disk" />
            <col class="col-alerts" />
          </colgroup>
          <thead>
            <tr>
              <th>Node{search && filteredNodes.length < nodes.length && <span class="nodes-search-count"> {filteredNodes.length}/{nodes.length}</span>}</th>
              <th>Cluster</th>
              <th>Role</th>
              <th>IP</th>
              <th>Arch</th>
              <th>OS</th>
              <th title={hasRealMetrics ? 'Real CPU utilization (5m avg)' : 'Kubernetes allocatable CPU (fixed per node)'}>CPU</th>
              <th title={hasRealMetrics ? 'Real memory utilization' : 'Kubernetes allocatable memory (fixed per node)'}>Memory</th>
              <th title={hasRealMetrics ? 'Real disk utilization on / filesystem' : 'Kubernetes allocatable ephemeral-storage (fixed per node)'}>Disk</th>
              <th>Alerts</th>
            </tr>
          </thead>
          <tbody>
            {groupedNodes.map(({ cluster, nodes: clusterNodes }) => (
              <>
                {showGroupHeaders && (
                  <tr class={`cluster-group-header cluster-group-header--${clusterBadgeSlug(cluster)}`}>
                    <td colspan={10}>
                      <span class={`node-cluster-badge ${clusterBadgeClass(cluster)}`}>{cluster}</span>
                      <span class="cluster-group-stats">
                        <span class={`cluster-ready-pill ${clusterNodes.filter(n => n.ready).length === clusterNodes.length ? 'cluster-ready-pill--all' : 'cluster-ready-pill--partial'}`}>
                          {clusterNodes.filter(n => n.ready).length}/{clusterNodes.length} ready
                        </span>
                        <span class="cluster-stat-sep">·</span>
                        <span class="cluster-stat">{Math.round(clusterNodes.reduce((s, n) => s + n.cpu_millicores, 0) / 1000)} vCPU</span>
                        <span class="cluster-stat-sep">·</span>
                        <span class="cluster-stat">{(clusterNodes.reduce((s, n) => s + n.memory_bytes, 0) / 1073741824).toFixed(0)} GiB RAM</span>
                      </span>
                    </td>
                  </tr>
                )}
                {clusterNodes.map((node) => (
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
              </>
            ))}
          </tbody>
        </table>
      </div>

      {/* ── Mobile card view (CSS shows/hides based on viewport) ── */}
      <div class="node-cards-mobile">
        {groupedNodes.map(({ cluster, nodes: clusterNodes }) => (
          <>
            {showGroupHeaders && (
              <div class={`cluster-card-header cluster-card-header--${clusterBadgeSlug(cluster)}`}>
                <span class={`node-cluster-badge ${clusterBadgeClass(cluster)}`}>{cluster}</span>
                <span class="cluster-card-stats">
                  {clusterNodes.filter(n => n.ready).length}/{clusterNodes.length} ready
                  &nbsp;·&nbsp;
                  {Math.round(clusterNodes.reduce((s, n) => s + n.cpu_millicores, 0) / 1000)} vCPU
                  &nbsp;·&nbsp;
                  {(clusterNodes.reduce((s, n) => s + n.memory_bytes, 0) / 1073741824).toFixed(0)} GiB
                </span>
              </div>
            )}
            {clusterNodes.map((node) => (
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
          </>
        ))}
      </div>
      <FleetCopilotTeaser />
      <p class="nodes-table-footnote">
        {hasRealMetrics
          ? 'Real host utilization via Prometheus node_exporter · Hover metrics to see details and sparkline.'
          : 'Allocatable capacity · not current host utilization'}
      </p>
    </div>
  );
}
