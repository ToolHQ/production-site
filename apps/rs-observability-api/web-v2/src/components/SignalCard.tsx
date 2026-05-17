import type { LiveOverview, MetricsData, Incident, RestartHotspot, CorootAlertsData, CorootIncidentsData } from '../types/api';
import { formatDiscreteCount } from '../utils/format';

// ────────────────────────────────────────────────────────────
// Helpers (lógica de negócio do boardLabel / nextActionText)
// ────────────────────────────────────────────────────────────

export function incidentsBySeverity(live: LiveOverview | null, severity: string): number {
  return (live?.incidents ?? []).filter((i) => i.severity === severity).length;
}

export function restartHotspots(metrics: MetricsData | null): RestartHotspot[] {
  return (metrics?.top_restarts ?? []).filter((item) => Math.round(Number(item.restarts_last_hour || 0)) > 0);
}

interface BoardLabel {
  tone: 'healthy' | 'warning' | 'critical';
  mode: string;
  score: string;
  copy: string;
}

export function boardLabel(
  live: LiveOverview | null,
  metrics: MetricsData | null,
  corootAlerts?: CorootAlertsData | null,
  corootIncidents?: CorootIncidentsData | null,
): BoardLabel {
  if (!live?.available) {
    return {
      tone: 'critical',
      mode: 'Snapshot fallback',
      score: 'Live unavailable',
      copy: live?.error || 'The in-cluster Kubernetes API is not reachable from this runtime.',
    };
  }

  const criticalIncidents = incidentsBySeverity(live, 'critical');
  const warningIncidents = incidentsBySeverity(live, 'warning');
  const downServices = live.summary.down_services || 0;
  const degradedServices = live.summary.degraded_services || 0;
  const restartingPods = live.summary.restarting_pods || 0;
  const hotspots = restartHotspots(metrics);

  // Coroot SLO incidents ativos (não resolvidos)
  const activeCorootIncidents = corootIncidents?.available
    ? corootIncidents.incidents.filter((i) => i.resolved_at === null)
    : [];
  const corootCritical = activeCorootIncidents.filter((i) => i.severity === 'critical').length;
  const corootWarning = activeCorootIncidents.filter((i) => i.severity === 'warning').length;
  // Alertas Coroot de alta criticidade contribuem como watchpoint se não há incidentes SLO
  const corootAlertCount = corootAlerts?.available ? corootAlerts.total : 0;

  const criticalWatch = criticalIncidents + downServices + corootCritical;
  const warningWatch =
    warningIncidents +
    degradedServices +
    (restartingPods > 0 ? 1 : 0) +
    hotspots.length +
    corootWarning +
    (corootAlertCount > 20 ? 1 : 0);

  if (criticalWatch > 0) {
    const corootNote = corootCritical > 0 ? ` · ${corootCritical} Coroot SLO critical` : '';
    return {
      tone: 'critical',
      mode: live.stale || metrics?.stale ? 'Immediate attention · stale signal' : 'Immediate attention',
      score: `${criticalWatch} blocker${criticalWatch === 1 ? '' : 's'}`,
      copy: `${criticalIncidents} K8s critical incident${criticalIncidents === 1 ? '' : 's'}, ${downServices} service${downServices === 1 ? '' : 's'} down${corootNote}.`,
    };
  }

  if (warningWatch > 0 || live.stale || metrics?.stale) {
    const corootNote = corootWarning > 0 ? ` · ${corootWarning} Coroot SLO warning` : (corootAlertCount > 20 ? ` · ${corootAlertCount} Coroot alerts` : '');
    return {
      tone: 'warning',
      mode: live.stale || metrics?.stale ? 'Guarded operation · stale cache' : 'Guarded operation',
      score: `${warningWatch || 1} watchpoint${warningWatch === 1 ? '' : 's'}`,
      copy: `No hard outage, but degraded services, warning incidents or restart debt still require follow-up${corootNote}.`,
    };
  }

  const allQuiet = corootAlertCount === 0 ? '' : ` ${corootAlertCount} Coroot alerts firing (below threshold).`;
  return {
    tone: 'healthy',
    mode: 'Live watch green',
    score: '0 blockers',
    copy: `No critical incident, no down service and no restart hotspot.${allQuiet}`,
  };
}

export function nextActionText(
  live: LiveOverview | null,
  metrics: MetricsData | null,
  corootAlerts?: CorootAlertsData | null,
  corootIncidents?: CorootIncidentsData | null,
): string {
  if (!live?.available) return 'Restore in-cluster Kubernetes API reachability before trusting the board.';

  const criticalIncident = live.incidents?.find((i: Incident) => i.severity === 'critical');
  const warningIncident = live.incidents?.find((i: Incident) => i.severity === 'warning');
  const hotspots = restartHotspots(metrics);

  const activeCorootIncidents = corootIncidents?.available
    ? corootIncidents.incidents.filter((i) => i.resolved_at === null)
    : [];
  const firstCorootCritical = activeCorootIncidents.find((i) => i.severity === 'critical');
  const firstCorootWarning = activeCorootIncidents.find((i) => i.severity === 'warning');

  if (criticalIncident) return `Inspect ${criticalIncident.resource} in ${criticalIncident.namespace}; ${criticalIncident.message}`;
  if (firstCorootCritical) return `Coroot SLO incident crítico: ${firstCorootCritical.application_id} — abrir coroot.dnor.io para detalhes.`;
  if ((live.summary.down_services || 0) > 0) return 'Open the critical service board and recover the first service marked down.';
  if (hotspots.length) return `Inspect ${hotspots[0].pod} in ${hotspots[0].namespace}; it carries the highest restart debt in the current window.`;
  if ((live.summary.degraded_services || 0) > 0) return 'Review degraded services before the board turns red.';
  if (warningIncident) return `Review ${warningIncident.resource} in ${warningIncident.namespace} before it escalates.`;
  if (firstCorootWarning) return `Coroot SLO incident warning: ${firstCorootWarning.application_id} — monitorar tendência no Coroot.`;
  if ((corootAlerts?.total ?? 0) > 20) return `${corootAlerts!.total} alertas Coroot ativos — revisar regras de maior frequência no Coroot.`;
  if (live.stale || metrics?.stale) return 'Fresh data is degraded; confirm the live data path before treating this as steady state.';
  return 'No immediate blocker. Stay on telemetry and watch for new restart hotspots.';
}

// ────────────────────────────────────────────────────────────
// Componente SignalCard
// ────────────────────────────────────────────────────────────

interface SignalCardProps {
  live: LiveOverview | null;
  corootAlerts?: CorootAlertsData | null;
  corootIncidents?: CorootIncidentsData | null;
}

export function SignalCard({ live, corootAlerts, corootIncidents }: SignalCardProps) {
  const metrics = live?.metrics ?? null;
  const board = boardLabel(live, metrics, corootAlerts, corootIncidents);
  const nextAction = nextActionText(live, metrics, corootAlerts, corootIncidents);
  const metricsInterval = live?.metrics?.refresh_interval_seconds ?? '--';

  return (
    <aside class="command-card" id="signal-card" data-tone={board.tone}>
      <div class="command-top">
        <div class="signal-badge">
          <span class="live-dot" />
          <span id="live-mode">{board.mode}</span>
        </div>
        <span id="auto-refresh">
          {live
            ? `Kube ${live.refresh_interval_seconds ?? '--'}s · Metrics ${metricsInterval}s`
            : 'Auto-refresh pending'}
        </span>
      </div>
      <div class="command-score" id="health-score">{board.score}</div>
      <p class="command-copy" id="health-copy">{board.copy}</p>
      <div class="next-step">
        <strong>Next action</strong>
        <span id="next-action">{nextAction}</span>
      </div>
    </aside>
  );
}

// ────────────────────────────────────────────────────────────
// Componente SignalGrid (mini contadores)
// ────────────────────────────────────────────────────────────

interface SignalGridProps {
  live: LiveOverview | null;
  corootAlerts?: CorootAlertsData | null;
  corootIncidents?: CorootIncidentsData | null;
}

export function SignalGrid({ live, corootAlerts, corootIncidents }: SignalGridProps) {
  const totalIncidents = incidentsBySeverity(live, 'critical') + incidentsBySeverity(live, 'warning');
  const servicesNeedingAction = (live?.summary.down_services || 0) + (live?.summary.degraded_services || 0);
  const firingAlerts = corootAlerts?.available ? corootAlerts.total : null;
  const activeIncidents = corootIncidents?.available
    ? corootIncidents.incidents.filter((i) => i.resolved_at === null).length
    : null;

  const items = [
    { value: live ? String(totalIncidents) : '--', label: 'K8s incidents' },
    { value: live ? String(servicesNeedingAction) : '--', label: 'Services needing action' },
    {
      value: live ? `${live.summary.nodes_ready ?? '--'}/${live.summary.nodes_total ?? '--'}` : '--/--',
      label: 'Ready nodes',
    },
    {
      value: live ? formatDiscreteCount(live.summary.restarting_pods ?? 0) : '--',
      label: 'Restarting pods',
    },
    {
      value: firingAlerts !== null ? String(firingAlerts) : '--',
      label: 'Coroot alerts',
    },
    {
      value: activeIncidents !== null ? String(activeIncidents) : '--',
      label: 'SLO incidents',
    },
  ];

  return (
    <section class="operator-grid" id="signal-grid">
      {items.map((item) => (
        <div class="signal-mini" key={item.label}>
          <strong>{item.value}</strong>
          <span>{item.label}</span>
        </div>
      ))}
    </section>
  );
}
