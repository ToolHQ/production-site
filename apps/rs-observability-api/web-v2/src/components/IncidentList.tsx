import type { LiveOverview } from '../types/api';

// ────────────────────────────────────────────────────────────
// IncidentList
// ────────────────────────────────────────────────────────────

interface IncidentListProps {
  live: LiveOverview | null;
}

export function IncidentList({ live }: IncidentListProps) {
  const incidents = (live?.incidents ?? []).slice(0, 6);

  return (
    <div class="incident-list" id="incident-list">
      {incidents.length > 0 ? (
        incidents.map((incident, idx) => (
          // key por índice é OK — lista pequena e sem reordenação local
          <article class="incident-item" key={`${incident.resource}-${idx}`}>
            <div class="incident-body">
              <strong>{incident.resource}</strong>
              <span>{incident.namespace} · {incident.message}</span>
            </div>
            <span class={`severity ${incident.severity}`}>{incident.severity}</span>
          </article>
        ))
      ) : (
        <article class="incident-item">
          <div class="incident-body">
            <strong>{live === null ? 'Waiting for cluster events' : 'No active incident'}</strong>
            <span>{live === null ? 'No live data yet.' : 'The live kube board is quiet right now.'}</span>
          </div>
          <span class="severity clear">clear</span>
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
    <div class="hotspot-list" id="restart-list">
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
            <strong>{metrics === null ? 'Waiting for Prometheus' : 'No restart hotspot'}</strong>
            <span>{metrics === null ? 'No hotspot data yet.' : 'The last hour is quiet for the tracked namespaces.'}</span>
          </div>
        </article>
      )}
    </div>
  );
}
