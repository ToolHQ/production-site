import type { LiveOverview, MetricsData, CorootAlertsData, CorootIncidentsData } from '../types/api';
import { ExportMenu } from './ExportMenu';
import { useRefreshCountdown } from '../hooks/useRefreshCountdown';
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
  corootAlerts?: CorootAlertsData | null;
  corootIncidents?: CorootIncidentsData | null;
}

function buildSnapshotPill(snapshot: SnapshotSummary | null): string {
  if (!snapshot?.generated_at) return 'Snapshot indisponível';
  const compact = isCompactViewport();
  const condensed = isCondensedViewport();
  if (compact) return `Snapshot · ${formatCompactRelativeTime(snapshot.generated_at)}`;
  if (condensed) return `Snapshot · ${formatRelativeTime(snapshot.generated_at).replace(/^generated\s/, '')}`;
  return `Snapshot · ${formatRelativeTime(snapshot.generated_at).replace(/^generated\s/, '')} · ${formatMetaDate(snapshot.generated_at)}`;
}

function buildLivePill(live: LiveOverview | null): string {
  if (!live) return 'Conectando API live…';
  const condensed = isCondensedViewport();
  return live.available
    ? `${condensed ? 'Live' : 'Live kube'} ${formatShortClock(live.refreshed_at_epoch)}${live.stale ? ' · stale' : ''}`
    : 'Live indisponível';
}

function buildMetricsPill(metrics: MetricsData | null): string {
  if (!metrics) return 'Conectando Prometheus…';
  const condensed = isCondensedViewport();
  return metrics.available
    ? `${condensed ? 'Prom' : 'Prometheus'} ${formatShortClock(metrics.refreshed_at_epoch)}${metrics.stale ? ' · stale' : ''}`
    : 'Prometheus indisponível';
}

type CorootPillTone = 'healthy' | 'warning' | 'critical' | 'offline';

function buildCorootPill(
  corootAlerts?: CorootAlertsData | null,
  corootIncidents?: CorootIncidentsData | null,
): { label: string; tone: CorootPillTone } {
  if (!corootAlerts?.available) return { label: 'Coroot offline', tone: 'offline' };

  const activeIncidents = corootIncidents?.available
    ? corootIncidents.incidents.filter((i) => i.resolved_at === null)
    : [];
  const criticalSlo = activeIncidents.filter((i) => i.severity === 'critical').length;
  const warningSlo = activeIncidents.filter((i) => i.severity === 'warning').length;
  const totalAlerts = corootAlerts.total;

  if (criticalSlo > 0) {
    return { label: `Coroot · ${criticalSlo} SLO critical`, tone: 'critical' };
  }
  if (warningSlo > 0 || totalAlerts > 20) {
    const detail = warningSlo > 0 ? `${warningSlo} SLO warn` : `${totalAlerts} alerts`;
    return { label: `Coroot · ${detail}`, tone: 'warning' };
  }
  return { label: `Coroot · ${totalAlerts} alerts`, tone: 'healthy' };
}

export function DashboardHeader({ snapshot, live, metrics, corootAlerts, corootIncidents }: HeaderProps) {
  const corootPill = buildCorootPill(corootAlerts, corootIncidents);
  const countdown = useRefreshCountdown(15_000, live?.refreshed_at_epoch ?? null);
  return (
    <div class="brand">
      <span class="eyebrow">Observabilidade operacional</span>
      <h1>Pulso do cluster para triagem</h1>
      <p class="subhead subhead--compact">
        Saúde live do Kubernetes e pressão Prometheus em primeiro plano — catálogo e deploy em segundo.
      </p>
      <div class="meta-row">
        <span class="pill" id="generated-at">{buildSnapshotPill(snapshot)}</span>
        <span class="pill" id="live-refresh">{buildLivePill(live)}</span>
        <span class="pill" id="metrics-refresh">{buildMetricsPill(metrics)}</span>
        <span class={`pill pill--coroot pill--coroot-${corootPill.tone}`} id="coroot-status">{corootPill.label}</span>
        <span class="pill pill--countdown" title="Próximo refresh dos dados live">🔄 {countdown}s</span>
        <ExportMenu live={live} metrics={metrics} />
      </div>
    </div>
  );
}
