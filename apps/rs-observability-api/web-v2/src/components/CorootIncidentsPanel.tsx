import type { CorootIncident, CorootIncidentsData } from '../types/api';
import styles from './CorootIncidentsPanel.module.css';

interface CorootIncidentsPanelProps {
  data: CorootIncidentsData | null;
  error: string | null;
  lastFetchAt: number | null;
}

const SEVERITY_ICON: Record<string, string> = {
  critical: '🔴',
  warning: '🟡',
  info: '🔵',
};

const COROOT_BASE_URL = 'https://coroot.dnor.io';

function formatDuration(ms: number): string {
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h${m % 60}m`;
  return `${Math.floor(h / 24)}d`;
}

function timeAgo(epochMs: number): string {
  const diff = Math.floor((Date.now() - epochMs) / 1000);
  if (diff < 60) return `${diff}s atrás`;
  const m = Math.floor(diff / 60);
  if (m < 60) return `${m}m atrás`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h atrás`;
  return `${Math.floor(h / 24)}d atrás`;
}

function incidentHref(incident: CorootIncident): string {
  const parts = incident.application_id.split(':');
  if (parts.length >= 2 && parts[0] !== 'external') {
    return `${COROOT_BASE_URL}/p/${parts[0]}/${encodeURIComponent(incident.application_id)}`;
  }
  return COROOT_BASE_URL;
}

function shortAppName(applicationId: string): string {
  const parts = applicationId.split(':');
  if (parts.length >= 4) return parts.slice(3).join(':');
  return applicationId;
}

function IncidentRow({ incident }: { incident: CorootIncident }) {
  const icon = SEVERITY_ICON[incident.severity] ?? '⚪';
  const isResolved = incident.resolved_at !== null;
  const name = shortAppName(incident.application_id);
  const href = incidentHref(incident);
  const dur = incident.duration > 0 ? formatDuration(incident.duration) : '';
  const ago = timeAgo(incident.opened_at);

  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      class={`${styles.row} ${isResolved ? styles.rowResolved : styles[`sev_${incident.severity}`] ?? ''}`}
      title={incident.short_description ?? incident.severity}
    >
      <span class={styles.icon} aria-hidden="true">
        {isResolved ? '✅' : icon}
      </span>
      <span class={styles.body}>
        <span class={styles.name}>{incident.short_description ?? incident.severity}</span>
        <span class={styles.meta}>
          {name} · {ago}{dur ? ` · duração ${dur}` : ''}
        </span>
      </span>
      {isResolved ? (
        <span class={`${styles.badge} ${styles.badgeResolved}`}>resolvido</span>
      ) : (
        <span class={`${styles.badge} ${styles[`badge_${incident.severity}`] ?? ''}`}>
          ativo
        </span>
      )}
    </a>
  );
}

export function CorootIncidentsPanel({ data, error, lastFetchAt }: CorootIncidentsPanelProps) {
  const incidents = data?.incidents ?? [];
  const activeCount = incidents.filter(i => i.resolved_at === null).length;
  const resolvedCount = incidents.filter(i => i.resolved_at !== null).length;

  const staleAge = lastFetchAt ? Math.floor((Date.now() - lastFetchAt) / 1000) : null;
  const isStale = staleAge !== null && staleAge > 90;

  return (
    <section class={styles.panel} aria-label="Coroot Incidents">
      <div class={styles.header}>
        <span class={styles.title}>
          Incidentes SLO
          {activeCount > 0 && (
            <span class={styles.countActive} title={`${activeCount} ativo(s)`}>
              {activeCount}
            </span>
          )}
          {resolvedCount > 0 && (
            <span class={styles.countResolved} title={`${resolvedCount} resolvido(s) recente(s)`}>
              +{resolvedCount}
            </span>
          )}
        </span>
        <a
          href={`${COROOT_BASE_URL}`}
          target="_blank"
          rel="noopener noreferrer"
          class={styles.corootLink}
          title="Abrir Coroot UI"
        >
          ↗
        </a>
      </div>

      {error && !data && (
        <div class={styles.errorState}>⚠️ {error}</div>
      )}

      {!data?.available && !error && (
        <div class={styles.errorState}>⚠️ {data?.error ?? 'Coroot indisponível'}</div>
      )}

      {!error && incidents.length === 0 && data?.available && (
        <div class={styles.emptyState}>
          <span class={styles.emptyIcon}>✅</span>
          <span>Nenhum incidente recente</span>
        </div>
      )}

      {incidents.length > 0 && (
        <ul class={styles.list} role="list">
          {incidents.map(inc => (
            <li key={inc.key} class={styles.listItem}>
              <IncidentRow incident={inc} />
            </li>
          ))}
        </ul>
      )}

      {isStale && (
        <div class={styles.staleNotice}>Dados com {staleAge}s de atraso</div>
      )}

      {lastFetchAt && !isStale && (
        <div class={styles.footer}>
          Sincronizado {Math.floor((Date.now() - lastFetchAt) / 1000)}s atrás · a cada 60s
        </div>
      )}
    </section>
  );
}
