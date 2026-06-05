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
      mode: 'Fallback snapshot',
      score: 'Live indisponível',
      copy: live?.error || 'API Kubernetes in-cluster inacessível neste runtime.',
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
    const corootNote = corootCritical > 0 ? ` · ${corootCritical} SLO Coroot crítico` : '';
    return {
      tone: 'critical',
      mode: live.stale || metrics?.stale ? 'Atenção imediata · sinal stale' : 'Atenção imediata',
      score: `${criticalWatch} bloqueio${criticalWatch === 1 ? '' : 's'}`,
      copy: `${criticalIncidents} incidente${criticalIncidents === 1 ? '' : 's'} crítico${criticalIncidents === 1 ? '' : 's'} K8s, ${downServices} serviço${downServices === 1 ? '' : 's'} down${corootNote}.`,
    };
  }

  if (warningWatch > 0 || live.stale || metrics?.stale) {
    const corootNote = corootWarning > 0 ? ` · ${corootWarning} SLO Coroot em alerta` : (corootAlertCount > 20 ? ` · ${corootAlertCount} alertas Coroot` : '');
    return {
      tone: 'warning',
      mode: live.stale || metrics?.stale ? 'Operação cautelosa · cache stale' : 'Operação cautelosa',
      score: `${warningWatch || 1} ponto${warningWatch === 1 ? '' : 's'} de atenção`,
      copy: `Sem outage duro, mas serviços degradados, incidentes ou dívida de restart exigem follow-up${corootNote}.`,
    };
  }

  const allQuiet = corootAlertCount === 0 ? '' : ` ${corootAlertCount} alertas Coroot abaixo do limiar crítico.`;
  return {
    tone: 'healthy',
    mode: 'Live em verde',
    score: '0 bloqueios',
    copy: `Sem incidente crítico, serviço down ou hotspot de restart.${allQuiet}`,
  };
}

export function nextActionText(
  live: LiveOverview | null,
  metrics: MetricsData | null,
  corootAlerts?: CorootAlertsData | null,
  corootIncidents?: CorootIncidentsData | null,
): string {
  if (!live?.available) return 'Restaure o acesso à API Kubernetes in-cluster antes de confiar no painel.';

  const criticalIncident = live.incidents?.find((i: Incident) => i.severity === 'critical');
  const warningIncident = live.incidents?.find((i: Incident) => i.severity === 'warning');
  const hotspots = restartHotspots(metrics);

  const activeCorootIncidents = corootIncidents?.available
    ? corootIncidents.incidents.filter((i) => i.resolved_at === null)
    : [];
  const firstCorootCritical = activeCorootIncidents.find((i) => i.severity === 'critical');
  const firstCorootWarning = activeCorootIncidents.find((i) => i.severity === 'warning');

  if (criticalIncident) {
    return `Inspecionar ${criticalIncident.resource} em ${criticalIncident.namespace}; ${criticalIncident.message}`;
  }
  if (firstCorootCritical) {
    return `SLO Coroot crítico: ${firstCorootCritical.application_id} — abrir coroot.dnor.io para detalhes.`;
  }
  if ((live.summary.down_services || 0) > 0) {
    return 'Abrir a grade de serviços críticos e recuperar o primeiro marcado como down.';
  }
  if (hotspots.length) {
    return `Inspecionar ${hotspots[0].pod} em ${hotspots[0].namespace}; maior dívida de restart na janela.`;
  }
  if ((live.summary.degraded_services || 0) > 0) {
    return 'Revisar serviços degradados antes do painel ficar vermelho.';
  }
  if (warningIncident) {
    return `Revisar ${warningIncident.resource} em ${warningIncident.namespace} antes de escalar.`;
  }
  if (firstCorootWarning) {
    return `SLO Coroot em alerta: ${firstCorootWarning.application_id} — monitorar tendência no Coroot.`;
  }
  if ((corootAlerts?.total ?? 0) > 20) {
    return `${corootAlerts!.total} alertas Coroot ativos — revisar regras de maior frequência.`;
  }
  if (live.stale || metrics?.stale) {
    return 'Dados stale; confirme o caminho live antes de tratar como estado estável.';
  }
  return 'Sem bloqueio imediato. Mantenha telemetria e observe novos hotspots de restart.';
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
            ? `Kube ${live.refresh_interval_seconds ?? '--'}s · Métricas ${metricsInterval}s`
            : 'Aguardando auto-refresh'}
        </span>
      </div>
      <div class="command-score" id="health-score">{board.score}</div>
      <p class="command-copy" id="health-copy">{board.copy}</p>
      <div class="next-step">
        <strong>Próxima ação</strong>
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
    { value: live ? String(totalIncidents) : '--', label: 'Incidentes K8s' },
    { value: live ? String(servicesNeedingAction) : '--', label: 'Serviços em risco' },
    {
      value: live ? `${live.summary.nodes_ready ?? '--'}/${live.summary.nodes_total ?? '--'}` : '--/--',
      label: 'Nós ready',
    },
    {
      value: live ? formatDiscreteCount(live.summary.restarting_pods ?? 0) : '--',
      label: 'Pods reiniciando',
    },
    {
      value: firingAlerts !== null ? String(firingAlerts) : '--',
      label: 'Alertas Coroot',
    },
    {
      value: activeIncidents !== null ? String(activeIncidents) : '--',
      label: 'Incidentes SLO',
    },
  ];

  return (
    <section class="operator-grid operator-grid--kpis" id="signal-grid" aria-label="Indicadores rápidos do cluster">
      {items.map((item) => (
        <div class="signal-mini" key={item.label}>
          <strong>{item.value}</strong>
          <span>{item.label}</span>
        </div>
      ))}
    </section>
  );
}
