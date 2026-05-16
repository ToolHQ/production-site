import type { LiveOverview, MetricsData, Incident, RestartHotspot } from '../types/api';
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

export function boardLabel(live: LiveOverview | null, metrics: MetricsData | null): BoardLabel {
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
  const criticalWatch = criticalIncidents + downServices;
  const warningWatch = warningIncidents + degradedServices + (restartingPods > 0 ? 1 : 0) + hotspots.length;

  if (criticalWatch > 0) {
    return {
      tone: 'critical',
      mode: live.stale || metrics?.stale ? 'Immediate attention · stale signal' : 'Immediate attention',
      score: `${criticalWatch} blocker${criticalWatch === 1 ? '' : 's'}`,
      copy: `${criticalIncidents} critical incident${criticalIncidents === 1 ? '' : 's'} and ${downServices} service${downServices === 1 ? '' : 's'} down are active on the board.`,
    };
  }

  if (warningWatch > 0 || live.stale || metrics?.stale) {
    return {
      tone: 'warning',
      mode: live.stale || metrics?.stale ? 'Guarded operation · stale cache' : 'Guarded operation',
      score: `${warningWatch || 1} watchpoint${warningWatch === 1 ? '' : 's'}`,
      copy: 'No hard outage, but degraded services, warning incidents or restart debt still require follow-up.',
    };
  }

  return {
    tone: 'healthy',
    mode: 'Live watch green',
    score: '0 blockers',
    copy: 'No critical incident, no down service and no restart hotspot are dominating the board right now.',
  };
}

export function nextActionText(live: LiveOverview | null, metrics: MetricsData | null): string {
  if (!live?.available) return 'Restore in-cluster Kubernetes API reachability before trusting the board.';

  const criticalIncident = live.incidents?.find((i: Incident) => i.severity === 'critical');
  const warningIncident = live.incidents?.find((i: Incident) => i.severity === 'warning');
  const hotspots = restartHotspots(metrics);

  if (criticalIncident) return `Inspect ${criticalIncident.resource} in ${criticalIncident.namespace}; ${criticalIncident.message}`;
  if ((live.summary.down_services || 0) > 0) return 'Open the critical service board and recover the first service marked down.';
  if (hotspots.length) return `Inspect ${hotspots[0].pod} in ${hotspots[0].namespace}; it carries the highest restart debt in the current window.`;
  if ((live.summary.degraded_services || 0) > 0) return 'Review degraded services before the board turns red.';
  if (warningIncident) return `Review ${warningIncident.resource} in ${warningIncident.namespace} before it escalates.`;
  if (live.stale || metrics?.stale) return 'Fresh data is degraded; confirm the live data path before treating this as steady state.';
  return 'No immediate blocker. Stay on telemetry and watch for new restart hotspots.';
}

// ────────────────────────────────────────────────────────────
// Componente SignalCard
// ────────────────────────────────────────────────────────────

interface SignalCardProps {
  live: LiveOverview | null;
}

export function SignalCard({ live }: SignalCardProps) {
  const metrics = live?.metrics ?? null;
  const board = boardLabel(live, metrics);
  const nextAction = nextActionText(live, metrics);
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
}

export function SignalGrid({ live }: SignalGridProps) {
  const totalIncidents = incidentsBySeverity(live, 'critical') + incidentsBySeverity(live, 'warning');
  const servicesNeedingAction = (live?.summary.down_services || 0) + (live?.summary.degraded_services || 0);

  const items = [
    { value: live ? String(totalIncidents) : '--', label: 'Active incidents' },
    { value: live ? String(servicesNeedingAction) : '--', label: 'Services needing action' },
    {
      value: live ? `${live.summary.nodes_ready ?? '--'}/${live.summary.nodes_total ?? '--'}` : '--/--',
      label: 'Ready nodes',
    },
    {
      value: live ? formatDiscreteCount(live.summary.restarting_pods ?? 0) : '--',
      label: 'Restarting pods',
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
