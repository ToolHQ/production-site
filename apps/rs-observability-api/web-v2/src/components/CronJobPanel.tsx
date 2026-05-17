import type { CronJobsData, CronJobInfo } from '../types/api';

interface CronJobPanelProps {
  data: CronJobsData | null;
  error: string | null;
}

function fmtTimestamp(ts: string | null): string {
  if (!ts) return '—';
  const d = new Date(ts);
  if (isNaN(d.getTime())) return ts;
  return d.toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function statusBadge(job: CronJobInfo): string {
  if (job.suspended) return 'cj-status cj-status--suspended';
  if (job.active > 0) return 'cj-status cj-status--running';
  if (job.last_run_succeeded === false) return 'cj-status cj-status--failed';
  if (job.last_run_succeeded === true) return 'cj-status cj-status--ok';
  return 'cj-status cj-status--unknown';
}

function statusLabel(job: CronJobInfo): string {
  if (job.suspended) return 'Suspenso';
  if (job.active > 0) return `Running (${job.active})`;
  if (job.last_run_succeeded === false) return 'Failed';
  if (job.last_run_succeeded === true) return 'OK';
  return 'Sem histórico';
}

export function CronJobPanel({ data, error }: CronJobPanelProps) {
  if (error && !data) {
    return (
      <div class="panel panel--error">
        <h2 class="panel-title">⏱ CronJobs</h2>
        <p class="panel-error">{error}</p>
      </div>
    );
  }

  if (!data) {
    return (
      <div class="panel panel--loading">
        <h2 class="panel-title">⏱ CronJobs</h2>
        <p class="panel-loading">Carregando…</p>
      </div>
    );
  }

  const sorted = [...data.cronjobs].sort((a, b) => {
    // Failed first, then suspended, then running, then ok
    const rank = (j: CronJobInfo) => {
      if (j.last_run_succeeded === false) return 0;
      if (j.suspended) return 1;
      if (j.active > 0) return 2;
      return 3;
    };
    return rank(a) - rank(b);
  });

  return (
    <div class="panel">
      <div class="panel-header">
        <h2 class="panel-title">⏱ CronJobs</h2>
        <div class="panel-summary">
          <span class="summary-badge summary-badge--ok">{data.healthy} OK</span>
          {data.failed > 0 && (
            <span class="summary-badge summary-badge--error">{data.failed} falhou</span>
          )}
          <span class="summary-badge summary-badge--neutral">{data.total} total</span>
        </div>
      </div>

      {error && <p class="panel-inline-warn">⚠ {error}</p>}

      <div class="panel-table-wrap">
        <table class="panel-table">
          <thead>
            <tr>
              <th>Nome</th>
              <th>Namespace</th>
              <th>Schedule</th>
              <th>Status</th>
              <th>Última execução</th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((cj) => (
              <tr key={`${cj.namespace}/${cj.name}`}>
                <td class="cj-name">{cj.name}</td>
                <td class="cj-ns">{cj.namespace}</td>
                <td class="cj-schedule"><code>{cj.schedule}</code></td>
                <td>
                  <span class={statusBadge(cj)}>{statusLabel(cj)}</span>
                </td>
                <td class="cj-last">{fmtTimestamp(cj.last_run_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
