import type { WorkloadsData, WorkloadInfo } from '../types/api';

interface WorkloadPanelProps {
  data: WorkloadsData | null;
  error: string | null;
}

const KIND_ICON: Record<string, string> = {
  Deployment: '🚀',
  StatefulSet: '🗄',
  DaemonSet: '🔷',
};

function statusClass(status: string): string {
  if (status === 'healthy') return 'wl-status wl-status--healthy';
  if (status === 'degraded') return 'wl-status wl-status--degraded';
  return 'wl-status wl-status--down';
}

function statusLabel(w: WorkloadInfo): string {
  if (w.status === 'healthy') return `${w.replicas_ready}/${w.replicas_desired}`;
  if (w.status === 'degraded') return `${w.replicas_ready}/${w.replicas_desired} ⚠`;
  return `0/${w.replicas_desired} ✗`;
}

export function WorkloadPanel({ data, error }: WorkloadPanelProps) {
  if (error && !data) {
    return (
      <div class="panel panel--error">
        <h2 class="panel-title">🚀 Workloads</h2>
        <p class="panel-error">{error}</p>
      </div>
    );
  }

  if (!data) {
    return (
      <div class="panel panel--loading">
        <h2 class="panel-title">🚀 Workloads</h2>
        <p class="panel-loading">Carregando…</p>
      </div>
    );
  }

  return (
    <div class="panel">
      <div class="panel-header">
        <h2 class="panel-title">🚀 Workloads</h2>
        <div class="panel-summary">
          <span class="summary-badge summary-badge--ok">{data.healthy} saudáveis</span>
          {data.degraded > 0 && (
            <span class="summary-badge summary-badge--warn">{data.degraded} degradados</span>
          )}
          {data.down > 0 && (
            <span class="summary-badge summary-badge--error">{data.down} down</span>
          )}
          <span class="summary-badge summary-badge--neutral">{data.total} total</span>
        </div>
      </div>

      {error && <p class="panel-inline-warn">⚠ {error}</p>}

      <div class="panel-table-wrap">
        <table class="panel-table">
          <thead>
            <tr>
              <th>Tipo</th>
              <th>Nome</th>
              <th>Namespace</th>
              <th>Réplicas</th>
              <th>Imagem</th>
            </tr>
          </thead>
          <tbody>
            {data.workloads.map((w: WorkloadInfo) => (
              <tr key={`${w.namespace}/${w.kind}/${w.name}`}>
                <td class="wl-kind">
                  <span title={w.kind}>{KIND_ICON[w.kind] ?? '📦'}</span>
                  <span class="wl-kind-label">{w.kind}</span>
                </td>
                <td class="wl-name">{w.name}</td>
                <td class="wl-ns">{w.namespace}</td>
                <td>
                  <span class={statusClass(w.status)}>{statusLabel(w)}</span>
                </td>
                <td class="wl-image" title={w.image}>{w.image || '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
