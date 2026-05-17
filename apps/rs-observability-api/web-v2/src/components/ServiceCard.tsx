import type { LiveOverview, CorootAlert, CorootIncident } from '../types/api';
import { statusClass, formatDiscreteCount } from '../utils/format';

const COROOT_BASE_URL = 'https://coroot.dnor.io';
const COROOT_PROJECT_ID = 'p3m78dle';

/** Find Coroot application_id matching a K8s service (by namespace + workload_name). */
function findCorootAppId(
  alerts: CorootAlert[],
  incidents: CorootIncident[],
  namespace: string,
  workloadName: string
): string | null {
  const nsKey = `:${namespace}:`;
  const nameKey = `:${workloadName}`;
  // Search alerts first (has more coverage)
  for (const a of alerts) {
    if (a.application_id.includes(nsKey) && a.application_id.endsWith(nameKey)) {
      return a.application_id;
    }
  }
  for (const i of incidents) {
    if (i.application_id.includes(nsKey) && i.application_id.endsWith(nameKey)) {
      return i.application_id;
    }
  }
  return null;
}

function corootHref(appId: string): string {
  return `${COROOT_BASE_URL}/p/${COROOT_PROJECT_ID}/${encodeURIComponent(appId)}`;
}

// ────────────────────────────────────────────────────────────
// ServiceCard (um serviço por card)
// ────────────────────────────────────────────────────────────

interface ServiceCardProps {
  service: LiveOverview['services'][number];
  alerts: CorootAlert[];
  incidents: CorootIncident[];
}

function ServiceCard({ service, alerts, incidents }: ServiceCardProps) {
  const nsKey = `:${service.namespace}:`;
  const nameKey = `:${service.workload_name}`;

  const serviceAlerts = alerts.filter(
    (a) => a.application_id.includes(nsKey) && a.application_id.endsWith(nameKey)
  );
  const activeIncidents = incidents.filter(
    (i) => i.application_id.includes(nsKey) && i.application_id.endsWith(nameKey) && i.resolved_at === null
  );

  const criticalAlerts = serviceAlerts.filter((a) => a.severity === 'critical').length;
  const warningAlerts = serviceAlerts.filter((a) => a.severity === 'warning').length;
  const appId = findCorootAppId(alerts, incidents, service.namespace, service.workload_name);
  const corootUrl = appId ? corootHref(appId) : null;

  return (
    <article class="service-card" data-status={service.status}>
      <div class="service-head">
        <div>
          <div class="service-name">
            {service.label}
            {activeIncidents.length > 0 && (
              <span
                class="coroot-incident-dot"
                title={`${activeIncidents.length} incidente(s) SLO ativo(s)`}
                aria-label="Incidente Coroot ativo"
              >
                ●
              </span>
            )}
          </div>
          <div class="service-subtitle">
            {service.namespace} · {service.workload_kind} · {service.workload_name}
          </div>
        </div>
        <div class="service-head-right">
          {(criticalAlerts > 0 || warningAlerts > 0) && (
            <span class="coroot-alert-badges">
              {criticalAlerts > 0 && (
                <span class="coroot-badge coroot-badge--critical" title={`${criticalAlerts} alerta(s) crítico(s) no Coroot`}>
                  🔴 {criticalAlerts}
                </span>
              )}
              {warningAlerts > 0 && (
                <span class="coroot-badge coroot-badge--warning" title={`${warningAlerts} aviso(s) no Coroot`}>
                  🟡 {warningAlerts}
                </span>
              )}
            </span>
          )}
          <span class={`status-pill ${statusClass(service.status)}`}>{service.status}</span>
        </div>
      </div>
      <p class="service-message">{service.message}</p>
      <div class="stat-row">
        <div class="stat-stack">
          <strong>{service.ready}/{service.desired}</strong>
          <span>ready vs desired</span>
        </div>
        <div class="stat-stack">
          <strong>{service.running_pods}/{service.pods_total}</strong>
          <span>running pods</span>
        </div>
        <div class="stat-stack">
          <strong>{formatDiscreteCount(service.restart_count)}</strong>
          <span>restart count</span>
        </div>
        <div class="stat-stack route-stack">
          <strong>{service.route || 'internal'}</strong>
          <span>primary route</span>
        </div>
      </div>
      {corootUrl && (
        <div class="service-coroot-link">
          <a href={corootUrl} target="_blank" rel="noopener noreferrer" title="Ver no Coroot">
            Coroot ↗
            {serviceAlerts.length > 0 && ` · ${serviceAlerts.length} alert${serviceAlerts.length !== 1 ? 's' : ''}`}
          </a>
        </div>
      )}
    </article>
  );
}

// ────────────────────────────────────────────────────────────
// ServiceGrid (container da seção)
// ────────────────────────────────────────────────────────────

interface ServiceGridProps {
  live: LiveOverview | null;
  alerts?: CorootAlert[];
  incidents?: CorootIncident[];
}

export function ServiceGrid({ live, alerts = [], incidents = [] }: ServiceGridProps) {
  const services = live?.services ?? [];

  return (
    <div class="service-grid" id="service-grid">
      {services.length > 0 ? (
        services.map((svc) => (
          <ServiceCard key={svc.id} service={svc} alerts={alerts} incidents={incidents} />
        ))
      ) : (
        <article class="service-card">
          <p class="empty">
            {live === null ? 'Loading live service board...' : 'Live service board unavailable.'}
          </p>
        </article>
      )}
    </div>
  );
}



