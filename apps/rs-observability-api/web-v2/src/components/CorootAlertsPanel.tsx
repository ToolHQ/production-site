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

function nodeFromInstance(instance: string): string {
  // "k8s-node-1:9100" → "k8s-node-1"
  return instance.split(':')[0];
}

function alertHref(alert: CorootAlert): string {
  const node = alert.node ?? nodeFromInstance(alert.instance);
  if (node && node !== 'unknown') {
    return `${COROOT_BASE_URL}/p/default?view=nodes`;
  }
  return COROOT_BASE_URL;
}

function AlertRow({ alert }: { alert: CorootAlert }) {
  const icon = SEVERITY_ICON[alert.severity] ?? '⚪';
  const node = alert.node ?? nodeFromInstance(alert.instance);
  const href = alertHref(alert);
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      class={`${styles.row} ${styles[`sev_${alert.severity}`] ?? ''}`}
      aria-label={`${alert.name} — ${alert.severity} em ${node}`}
    >
      <span class={styles.icon} aria-hidden="true">{icon}</span>
      <span class={styles.body}>
        <span class={styles.name}>{alert.name}</span>
        <span class={styles.meta}>
          {node !== 'unknown' ? node : alert.instance}
          {alert.namespace ? ` · ${alert.namespace}` : ''}
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

      {!error && alerts.length === 0 && (
        <div class={styles.emptyState}>
          <span class={styles.emptyIcon}>✅</span>
          <span>Nenhum alerta ativo</span>
        </div>
      )}

      {sorted.length > 0 && (
        <ul class={styles.list} role="list">
          {sorted.map((alert, idx) => (
            <li key={`${alert.name}-${alert.instance}-${idx}`} class={styles.listItem}>
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
