import type { LiveOverview } from '../types/api';
import { statusClass, formatDiscreteCount } from '../utils/format';

// ────────────────────────────────────────────────────────────
// ServiceCard (um serviço por card)
// ────────────────────────────────────────────────────────────

interface ServiceCardProps {
  service: LiveOverview['services'][number];
}

function ServiceCard({ service }: ServiceCardProps) {
  return (
    <article class="service-card" data-status={service.status}>
      <div class="service-head">
        <div>
          <div class="service-name">{service.label}</div>
          <div class="service-subtitle">
            {service.namespace} · {service.workload_kind} · {service.workload_name}
          </div>
        </div>
        <span class={`status-pill ${statusClass(service.status)}`}>{service.status}</span>
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
    </article>
  );
}

// ────────────────────────────────────────────────────────────
// ServiceGrid (container da seção)
// ────────────────────────────────────────────────────────────

interface ServiceGridProps {
  live: LiveOverview | null;
}

export function ServiceGrid({ live }: ServiceGridProps) {
  const services = live?.services ?? [];

  return (
    <div class="service-grid" id="service-grid">
      {services.length > 0 ? (
        services.map((svc) => <ServiceCard key={svc.id} service={svc} />)
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
