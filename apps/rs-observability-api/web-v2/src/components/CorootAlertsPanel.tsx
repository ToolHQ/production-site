import type { CorootAlert, CorootAlertsData } from '../types/api';
import styles from './CorootAlertsPanel.module.css';

interface CorootAlertsPanelProps {
  data: CorootAlertsData | null;
  error: string | null;
  lastFetchAt: number | null;
}

const SEVERITY_ICON: Record<string, string> = {
  critical: '🔴',
  warning: '🟡',
  info: '🔵',
};

const COROOT_BASE_URL = 'https://coroot.dnor.io';

function severityLabel(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

/** Parse "p3m78dle:namespace:Kind:name" → { namespace, kind, name } */
function parseAppId(applicationId: string): { namespace: string; kind: string; name: string } {
  const parts = applicationId.split(':');
  if (parts.length >= 4) {
    const namespace = parts[1] === '_' || parts[1] === 'external' ? parts[2] : parts[1];
    const kind = parts[2];
    const name = parts.slice(3).join(':');
    return { namespace, kind, name };
  }
  return { namespace: '', kind: '', name: applicationId };
}

function alertHref(alert: CorootAlert): string {
  const parts = alert.application_id.split(':');
  if (parts.length >= 2 && parts[0] !== 'external') {
    return `${COROOT_BASE_URL}/p/${parts[0]}/${encodeURIComponent(alert.application_id)}`;
  }
  return COROOT_BASE_URL;
}

function formatDuration(ms: number): string {
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h`;
  return `${Math.floor(h / 24)}d`;
}

function AlertRow({ alert }: { alert: CorootAlert }) {
  const icon = SEVERITY_ICON[alert.severity] ?? '⚪';
  const { namespace, name } = parseAppId(alert.application_id);
  const href = alertHref(alert);
  const durationStr = alert.duration > 0 ? formatDuration(alert.duration) : '';
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      class={`${styles.row} ${styles[`sev_${alert.severity}`] ?? ''}`}
      aria-label={`${alert.rule_name} — ${alert.severity} em ${name}`}
      title={alert.summary}
    >
      <span class={styles.icon} aria-hidden="true">{icon}</span>
      <span class={styles.body}>
        <span class={styles.name}>{alert.summary}</span>
        <span class={styles.meta}>
          {name}
          {namespace ? ` · ${namespace}` : ''}
          {durationStr ? ` · ${durationStr}` : ''}
        </span>
      </span>
      <span class={`${styles.badge} ${styles[`badge_${alert.severity}`] ?? ''}`}>
        {severityLabel(alert.severity)}
      </span>
    </a>
  );
}

export function CorootAlertsPanel({ data, error, lastFetchAt }: CorootAlertsPanelProps) {
  const alerts = data?.alerts ?? [];
  const criticalCount = alerts.filter(a => a.severity === 'critical').length;
  const warningCount = alerts.filter(a => a.severity === 'warning').length;
  const total = data?.total ?? alerts.length;

  const staleAge = lastFetchAt ? Math.floor((Date.now() - lastFetchAt) / 1000) : null;
  const isStale = staleAge !== null && staleAge > 90;

  // Sort: critical first, then warning, then info
  const sorted = [...alerts].sort((a, b) => {
    const order: Record<string, number> = { critical: 0, warning: 1, info: 2 };
    return (order[a.severity] ?? 3) - (order[b.severity] ?? 3);
  });

  return (
    <section class={styles.panel} aria-label="Coroot Alerts">
      <div class={styles.header}>
        <span class={styles.title}>
          Coroot Alerts
          {criticalCount > 0 && (
            <span class={styles.countCritical} title={`${criticalCount} crítico(s)`}>
              {criticalCount}
            </span>
          )}
          {warningCount > 0 && (
            <span class={styles.countWarning} title={`${warningCount} aviso(s)`}>
              {warningCount}
            </span>
          )}
          {total > 0 && (
            <span class={styles.totalCount} title={`${total} alerta(s) total`}>
              ({total})
            </span>
          )}
        </span>
        <a
          href={COROOT_BASE_URL}
          target="_blank"
          rel="noopener noreferrer"
          class={styles.corootLink}
          title="Abrir Coroot UI"
        >
          ↗
        </a>
      </div>

      {error && !data && (
        <div class={styles.errorState}>
          <span>⚠️ {error}</span>
        </div>
      )}

      {!error && alerts.length === 0 && data?.available && (
        <div class={styles.emptyState}>
          <span class={styles.emptyIcon}>✅</span>
          <span>Nenhum alerta ativo</span>
        </div>
      )}

      {!data?.available && !error && (
        <div class={styles.errorState}>
          <span>⚠️ {data?.error ?? 'Coroot indisponível'}</span>
        </div>
      )}

      {sorted.length > 0 && (
        <ul class={styles.list} role="list">
          {sorted.map((alert, idx) => (
            <li key={`${alert.id}-${idx}`} class={styles.listItem}>
              <AlertRow alert={alert} />
            </li>
          ))}
        </ul>
      )}

      {isStale && (
        <div class={styles.staleNotice}>Dados com {staleAge}s de atraso</div>
      )}

      {lastFetchAt && !isStale && (
        <div class={styles.footer}>
          Sincronizado {Math.floor((Date.now() - lastFetchAt) / 1000)}s atrás · a cada 30s
        </div>
      )}
    </section>
  );
}
