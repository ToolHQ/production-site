import type { MetricsData, LiveOverview } from '../types/api';
import { formatCores, formatBytes, formatDiscreteCount, statusClass } from '../utils/format';
import { MetricSparkline } from './MetricSparkline';

// ────────────────────────────────────────────────────────────
// TelemetryCard (um serviço por card)
// ────────────────────────────────────────────────────────────

interface TelemetryCardProps {
  service: MetricsData['services'][number];
  liveService?: LiveOverview['services'][number] | null;
  windowMinutes: number;
}

function TelemetryCard({ service, liveService, windowMinutes }: TelemetryCardProps) {
  const liveStatus = liveService?.status ?? 'telemetry';
  const route = liveService?.route ?? 'internal route';
  const restartCount = liveService ? formatDiscreteCount(liveService.restart_count) : '--';

  return (
    <article class="telemetry-card" data-tone={liveStatus}>
      <div class="telemetry-header">
        <div>
          <div class="telemetry-name">{service.label}</div>
          <div class="telemetry-support">
            Prometheus {windowMinutes}m window · {route} · {restartCount} live restarts
          </div>
        </div>
        <span class={`status-pill ${statusClass(liveStatus)}`}>{liveStatus}</span>
      </div>
      <div class="telemetry-grid-mini">
        <div class="telemetry-mini">
          <strong class="telemetry-value">{formatCores(service.cpu_cores_latest)}</strong>
          <span class="telemetry-meta">CPU in use</span>
          <MetricSparkline points={service.cpu_series ?? []} color="#0d7c72" />
        </div>
        <div class="telemetry-mini">
          <strong class="telemetry-value">{formatBytes(service.memory_bytes_latest)}</strong>
          <span class="telemetry-meta">Memory RSS</span>
          <MetricSparkline points={service.memory_series ?? []} color="#c96633" />
        </div>
      </div>
    </article>
  );
}

// ────────────────────────────────────────────────────────────
// TelemetryGrid (container da seção)
// ────────────────────────────────────────────────────────────

interface TelemetryGridProps {
  metrics: MetricsData | null;
  live: LiveOverview | null;
}

export function TelemetryGrid({ metrics, live }: TelemetryGridProps) {
  const services = metrics?.services ?? [];
  const liveMap = new Map((live?.services ?? []).map((s) => [s.id, s]));

  return (
    <div class="telemetry-grid" id="telemetry-grid">
      {services.length > 0 ? (
        services.map((svc) => (
          <TelemetryCard
            key={svc.id}
            service={svc}
            liveService={liveMap.get(svc.id) ?? null}
            windowMinutes={metrics?.window_minutes ?? 0}
          />
        ))
      ) : (
        <article class="telemetry-card">
          <p class="empty">
            {metrics === null
              ? 'Waiting for Prometheus time-series...'
              : 'No Prometheus time-series available for tracked services.'}
          </p>
        </article>
      )}
    </div>
  );
}
