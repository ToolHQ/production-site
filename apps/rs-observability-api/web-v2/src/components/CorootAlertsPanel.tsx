import { useState } from 'preact/hooks';
import type { CorootAlert, CorootAlertsData } from '../types/api';
import styles from './CorootAlertsPanel.module.css';

interface CorootAlertsPanelProps {
  data: CorootAlertsData | null;
  error: string | null;
  lastFetchAt: number | null;
}

const SEVERITY_ORDER: Record<string, number> = { critical: 0, warning: 1, info: 2 };
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

function alertHref(alert: CorootAlert): string {
  const parts = alert.application_id.split(':');
  if (parts.length >= 2 && parts[0] !== 'external') {
    return `${COROOT_BASE_URL}/p/${parts[0]}/${encodeURIComponent(alert.application_id)}`;
  }
  return COROOT_BASE_URL;
}

/** Returns the worst severity in a group */
function groupSeverity(alerts: CorootAlert[]): string {
  return alerts.reduce((worst, a) => {
    return (SEVERITY_ORDER[a.severity] ?? 9) < (SEVERITY_ORDER[worst] ?? 9) ? a.severity : worst;
  }, 'info');
}

/** Parse "p3m78dle:namespace:Kind:name" → display name */
function shortName(applicationId: string): string {
  const parts = applicationId.split(':');
  if (parts.length >= 4) return parts.slice(3).join(':');
  return applicationId;
}

interface AlertGroup {
  rule_name: string;
  severity: string;
  alerts: CorootAlert[];
}

function buildGroups(alerts: CorootAlert[]): AlertGroup[] {
  const map = new Map<string, CorootAlert[]>();
  for (const a of alerts) {
    const key = a.rule_name;
    if (!map.has(key)) map.set(key, []);
    map.get(key)!.push(a);
  }
  const groups: AlertGroup[] = [];
  for (const [rule_name, list] of map) {
    groups.push({ rule_name, severity: groupSeverity(list), alerts: list });
  }
  groups.sort((a, b) => {
    const sd = (SEVERITY_ORDER[a.severity] ?? 9) - (SEVERITY_ORDER[b.severity] ?? 9);
    if (sd !== 0) return sd;
    return b.alerts.length - a.alerts.length;
  });
  return groups;
}

function AlertGroupRow({ group }: { group: AlertGroup }) {
  const [expanded, setExpanded] = useState(false);
  const icon = SEVERITY_ICON[group.severity] ?? '⚪';
  const worst = group.alerts[0];
  const href = alertHref(worst);
  const maxDuration = Math.max(...group.alerts.map(a => a.duration ?? 0));

  return (
    <li class={styles.listItem}>
      <div class={`${styles.groupRow} ${styles[`sev_${group.severity}`] ?? ''}`}>
        <a
          href={href}
          target="_blank"
          rel="noopener noreferrer"
          class={styles.groupLink}
          title={`Ver ${group.rule_name} no Coroot`}
        >
          <span class={styles.icon} aria-hidden="true">{icon}</span>
          <span class={styles.body}>
            <span class={styles.name}>{group.rule_name}</span>
            <span class={styles.meta}>
              {group.alerts.length} serviço{group.alerts.length !== 1 ? 's' : ''}
              {maxDuration > 0 ? ` · até ${formatDuration(maxDuration)}` : ''}
            </span>
          </span>
        </a>
        {group.alerts.length > 1 && (
          <button
            class={styles.expandBtn}
            aria-expanded={expanded}
            aria-label={expanded ? 'Recolher' : 'Expandir'}
            onClick={() => setExpanded(v => !v)}
          >
            <span class={`${styles.expandIcon} ${expanded ? styles.expandIconOpen : ''}`}>›</span>
          </button>
        )}
        <span class={`${styles.badge} ${styles[`badge_${group.severity}`] ?? ''}`}>
          {group.alerts.length}
        </span>
      </div>

      {expanded && group.alerts.length > 1 && (
        <ul class={styles.subList}>
          {group.alerts.map((alert, idx) => {
            const name = shortName(alert.application_id);
            const dur = alert.duration > 0 ? formatDuration(alert.duration) : '';
            return (
              <li key={`${alert.id}-${idx}`}>
                <a
                  href={alertHref(alert)}
                  target="_blank"
                  rel="noopener noreferrer"
                  class={styles.subRow}
                  title={alert.summary}
                >
                  <span class={styles.subName}>{name}</span>
                  {dur && <span class={styles.subDur}>{dur}</span>}
                </a>
              </li>
            );
          })}
        </ul>
      )}
    </li>
  );
}

export function CorootAlertsPanel({ data, error, lastFetchAt }: CorootAlertsPanelProps) {
  const alerts = data?.alerts ?? [];
  const criticalCount = alerts.filter(a => a.severity === 'critical').length;
  const warningCount = alerts.filter(a => a.severity === 'warning').length;
  const total = data?.total ?? alerts.length;

  const staleAge = lastFetchAt ? Math.floor((Date.now() - lastFetchAt) / 1000) : null;
  const isStale = staleAge !== null && staleAge > 90;

  const groups = buildGroups(alerts);

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
            <span class={styles.totalCount} title={`${total} alertas em ${groups.length} regras`}>
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

      {groups.length > 0 && (
        <ul class={styles.list} role="list">
          {groups.map(g => (
            <AlertGroupRow key={g.rule_name} group={g} />
          ))}
        </ul>
      )}

      {isStale && (
        <div class={styles.staleNotice}>Dados com {staleAge}s de atraso</div>
      )}

      {lastFetchAt && !isStale && (
        <div class={styles.footer}>
          Sincronizado {Math.floor((Date.now() - lastFetchAt) / 1000)}s atrás · a cada 30s
          {groups.length > 0 && ` · ${groups.length} regras`}
        </div>
      )}
    </section>
  );
}

