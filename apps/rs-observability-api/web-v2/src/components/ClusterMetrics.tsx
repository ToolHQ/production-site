import type { MetricsData } from '../types/api';
import { formatPercent, formatCores, formatBytes, formatDiscreteCount } from '../utils/format';
import { MetricSparkline } from './MetricSparkline';

// ────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────

function deltaFromSeries(points: Array<{ value: number }> | undefined): number | null {
  const values = (points ?? []).filter((p) => Number.isFinite(p.value));
  if (values.length < 2) return null;
  return values[values.length - 1].value - values[0].value;
}

function describeDelta(kind: string, delta: number | null): string {
  if (!Number.isFinite(delta as number) || delta === null) return 'trend unavailable';

  if (kind === 'restart') {
    const rounded = Math.round(Math.abs(delta));
    if (rounded < 1) return 'stable vs window start';
    return delta > 0 ? `+${rounded} events vs window start` : `${rounded} fewer events vs window start`;
  }

  const absDelta = Math.abs(delta);
  if (absDelta < 1.5) return 'steady vs window start';
  return delta > 0
    ? `rising ${absDelta.toFixed(1)} pts vs window start`
    : `down ${absDelta.toFixed(1)} pts vs window start`;
}

interface MetricState {
  tone: 'healthy' | 'warning' | 'critical';
  badge: string;
}

function metricState(kind: string, value: number): MetricState {
  if (kind === 'restart') {
    if (value >= 10) return { tone: 'critical', badge: 'Restart spike' };
    if (value > 0) return { tone: 'warning', badge: 'Restarts active' };
    return { tone: 'healthy', badge: 'Quiet hour' };
  }
  if (kind === 'cpu') {
    if (value >= 85) return { tone: 'critical', badge: 'High load' };
    if (value >= 65) return { tone: 'warning', badge: 'Elevated' };
    return { tone: 'healthy', badge: 'Within headroom' };
  }
  // memory
  if (value >= 85) return { tone: 'critical', badge: 'Memory pressure' };
  if (value >= 70) return { tone: 'warning', badge: 'Warm memory' };
  return { tone: 'healthy', badge: 'Within headroom' };
}

// ────────────────────────────────────────────────────────────
// Componente único MetricCard
// ────────────────────────────────────────────────────────────

interface MetricCardProps {
  label: string;
  value: string;
  meta: string;
  note: string;
  color: string;
  series: Array<{ timestamp: number; value: number }>;
  state: MetricState;
}

function MetricCard({ label, value, meta, note, color, series, state }: MetricCardProps) {
  return (
    <article class="metric-card" data-tone={state.tone}>
      <div class="metric-top">
        <div>
          <div class="metric-label">{label}</div>
          <strong class="metric-value">{value}</strong>
          <div class="metric-meta">{meta}</div>
        </div>
        <span class={`trend-chip ${state.tone}`}>{state.badge}</span>
      </div>
      <div class="metric-note">{note}</div>
      <MetricSparkline points={series} color={color} />
    </article>
  );
}

// ────────────────────────────────────────────────────────────
// Seção ClusterMetrics (grid de 3 cards)
// ────────────────────────────────────────────────────────────

interface ClusterMetricsProps {
  metrics: MetricsData | null;
}

export function ClusterMetrics({ metrics }: ClusterMetricsProps) {
  if (!metrics?.available) {
    return (
      <div class="metric-grid" id="cluster-metrics">
        <article class="metric-card">
          <div class="metric-label">Prometheus unavailable</div>
          <div class="metric-meta">{metrics?.error ?? 'The console could not fetch time-series yet.'}</div>
        </article>
      </div>
    );
  }

  const cluster = metrics.cluster;
  const cpuState = metricState('cpu', Number(cluster.cpu_percent_latest || 0));
  const memoryState = metricState('memory', Number(cluster.memory_percent_latest || 0));
  const restartState = metricState('restart', Number(cluster.restart_events_last_hour || 0));

  const cards: MetricCardProps[] = [
    {
      label: 'Cluster CPU',
      value: formatPercent(cluster.cpu_percent_latest),
      meta: `${formatCores(cluster.cpu_cores_used_latest)} in use · ${metrics.window_minutes}m window`,
      note: describeDelta('cpu', deltaFromSeries(cluster.cpu_percent_series)),
      color: '#0d7c72',
      series: cluster.cpu_percent_series || [],
      state: cpuState,
    },
    {
      label: 'Cluster Memory',
      value: formatPercent(cluster.memory_percent_latest),
      meta: `${formatBytes(cluster.memory_bytes_used_latest)} working set · ${metrics.window_minutes}m window`,
      note: describeDelta('memory', deltaFromSeries(cluster.memory_percent_series)),
      color: '#c96633',
      series: cluster.memory_percent_series || [],
      state: memoryState,
    },
    {
      label: 'Restart Pressure',
      value: formatDiscreteCount(cluster.restart_events_last_hour),
      meta: 'restart events recorded over the last hour',
      note: describeDelta('restart', deltaFromSeries(cluster.restart_pressure_series)),
      color: '#c03b2b',
      series: cluster.restart_pressure_series || [],
      state: restartState,
    },
  ];

  return (
    <div class="metric-grid" id="cluster-metrics">
      {cards.map((card) => (
        <MetricCard key={card.label} {...card} />
      ))}
    </div>
  );
}
