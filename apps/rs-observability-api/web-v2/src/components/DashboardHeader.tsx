import type { LiveOverview, MetricsData } from '../types/api';
import { ThemeToggle } from './ThemeToggle';
import {
  formatCompactRelativeTime,
  formatRelativeTime,
  formatMetaDate,
  formatShortClock,
  isCompactViewport,
  isCondensedViewport,
} from '../utils/format';
import type { SnapshotSummary } from '../types/api';

interface HeaderProps {
  snapshot: SnapshotSummary | null;
  live: LiveOverview | null;
  metrics: MetricsData | null;
}

function buildSnapshotPill(snapshot: SnapshotSummary | null): string {
  if (!snapshot?.generated_at) return 'Snapshot unavailable';
  const compact = isCompactViewport();
  const condensed = isCondensedViewport();
  if (compact) return `Snapshot · ${formatCompactRelativeTime(snapshot.generated_at)}`;
  if (condensed) return `Snapshot · ${formatRelativeTime(snapshot.generated_at).replace(/^generated\s/, '')}`;
  return `Snapshot · ${formatRelativeTime(snapshot.generated_at).replace(/^generated\s/, '')} · ${formatMetaDate(snapshot.generated_at)}`;
}

function buildLivePill(live: LiveOverview | null): string {
  if (!live) return 'Connecting to live cluster API...';
  const condensed = isCondensedViewport();
  return live.available
    ? `${condensed ? 'Live' : 'Live kube'} ${formatShortClock(live.refreshed_at_epoch)}${live.stale ? ' · stale' : ''}`
    : 'Live unavailable';
}

function buildMetricsPill(metrics: MetricsData | null): string {
  if (!metrics) return 'Connecting to Prometheus...';
  const condensed = isCondensedViewport();
  return metrics.available
    ? `${condensed ? 'Prom' : 'Prometheus'} ${formatShortClock(metrics.refreshed_at_epoch)}${metrics.stale ? ' · stale' : ''}`
    : 'Prometheus unavailable';
}

export function DashboardHeader({ snapshot, live, metrics }: HeaderProps) {
  return (
    <div class="brand">
      <span class="eyebrow">Operations-first observability</span>
      <h1>Cluster pulse for triage, not just reporting.</h1>
      <p class="subhead">
        Live Kubernetes health and Prometheus pressure stay in the foreground.
        Catalog and deploy context remain available, but secondary.
      </p>
      <div class="meta-row">
        <span class="pill" id="generated-at">{buildSnapshotPill(snapshot)}</span>
        <span class="pill" id="live-refresh">{buildLivePill(live)}</span>
        <span class="pill" id="metrics-refresh">{buildMetricsPill(metrics)}</span>
        <ThemeToggle />
      </div>
    </div>
  );
}
