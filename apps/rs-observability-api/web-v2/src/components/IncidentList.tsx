import type { LiveOverview } from '../types/api';

// ────────────────────────────────────────────────────────────
// IncidentList
// ────────────────────────────────────────────────────────────

interface IncidentListProps {
  live: LiveOverview | null;
}

export function IncidentList({ live }: IncidentListProps) {
  const incidents = (live?.incidents ?? []).slice(0, 6);

  const severityLabel = (s: string) => {
    if (s === 'critical') return 'Crítico';
    if (s === 'warning') return 'Alerta';
    return s;
  };

  return (
    <div class="incident-list tabular-nums" id="incident-list">
      {incidents.length > 0 ? (
        incidents.map((incident, idx) => (
          <article class="incident-item" key={`${incident.resource}-${idx}`}>
            <div class="incident-body">
              <strong>{incident.resource}</strong>
              <span>{incident.namespace} · {incident.message}</span>
            </div>
            <span class={`severity ${incident.severity}`}>{severityLabel(incident.severity)}</span>
          </article>
        ))
      ) : (
        <article class="incident-item">
          <div class="incident-body">
            <strong>{live === null ? 'Aguardando eventos do cluster' : 'Nenhum incidente ativo'}</strong>
            <span>{live === null ? 'Conectando à API live…' : 'Nada crítico no momento.'}</span>
          </div>
          <span class="severity clear">ok</span>
        </article>
      )}
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// RestartHotspots
// ────────────────────────────────────────────────────────────

import type { MetricsData } from '../types/api';
import { formatDiscreteCount } from '../utils/format';

interface RestartHotspotsProps {
  metrics: MetricsData | null;
}

export function RestartHotspots({ metrics }: RestartHotspotsProps) {
  const hotspots = (metrics?.top_restarts ?? [])
    .filter((item) => Math.round(Number(item.restarts_last_hour || 0)) > 0)
    .slice(0, 6);

  return (
    <div class="hotspot-list tabular-nums" id="restart-list">
      {hotspots.length > 0 ? (
        hotspots.map((item, idx) => (
          <article class="hotspot-item" key={`${item.pod}-${idx}`}>
            <div class="hotspot-body">
              <strong>{item.pod}</strong>
              <span>{item.namespace}</span>
            </div>
            <strong class="hotspot-value">{formatDiscreteCount(item.restarts_last_hour)}</strong>
          </article>
        ))
      ) : (
        <article class="hotspot-item">
          <div class="hotspot-body">
            <strong>{metrics === null ? 'Aguardando Prometheus' : 'Sem hotspot de restart'}</strong>
            <span>{metrics === null ? 'Coletando métricas…' : 'Última hora tranquila nos namespaces monitorados.'}</span>
          </div>
        </article>
      )}
    </div>
  );
}
