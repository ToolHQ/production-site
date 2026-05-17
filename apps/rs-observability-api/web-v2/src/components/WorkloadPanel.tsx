import { useState } from 'preact/hooks';
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

const STATUS_RANK: Record<string, number> = { down: 0, degraded: 1, healthy: 2 };

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

function shortImage(image: string): string {
  if (!image) return '—';
  const withoutRegistry = image.replace(/^[^/]+\.[^/]+(?::\d+)?\//, '');
  const lastSlash = withoutRegistry.lastIndexOf('/');
  return lastSlash >= 0 ? withoutRegistry.slice(lastSlash + 1) : withoutRegistry;
}

export function WorkloadPanel({ data, error }: WorkloadPanelProps) {
  const [nsFilter, setNsFilter] = useState('');

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

  const namespaces = [...new Set(data.workloads.map((w) => w.namespace))].sort();

  const sorted = [...data.workloads]
    .filter((w) => !nsFilter || w.namespace === nsFilter)
    .sort((a, b) => {
      const ra = STATUS_RANK[a.status] ?? 99;
      const rb = STATUS_RANK[b.status] ?? 99;
      return ra !== rb ? ra - rb : a.name.localeCompare(b.name);
    });

  return (
    <div class="panel">
      <div class="panel-header">
        <h2 class="panel-title">🚀 Workloads</h2>
        <div class="wl-header-right">
          {namespaces.length > 1 && (
            <select
              class="wl-ns-filter"
              value={nsFilter}
              onChange={(e) => setNsFilter((e.target as HTMLSelectElement).value)}
            >
              <option value="">Todos os namespaces</option>
              {namespaces.map((ns) => (
                <option key={ns} value={ns}>{ns}</option>
              ))}
            </select>
          )}
          <div class="panel-summary">
            {data.down > 0 && (
              <span class="summary-badge summary-badge--error">{data.down} down</span>
            )}
            {data.degraded > 0 && (
              <span class="summary-badge summary-badge--warn">{data.degraded} degradados</span>
            )}
            <span class="summary-badge summary-badge--ok">{data.healthy} saudáveis</span>
            <span class="summary-badge summary-badge--neutral">{data.total} total</span>
          </div>
        </div>
      </div>

      {error && <p class="panel-inline-warn">⚠ {error}</p>}

      <div class="wl-table-wrap">
        <table class="wl-table">
          <thead>
            <tr>
              <th class="wl-th">Tipo</th>
              <th class="wl-th">Nome / Namespace</th>
              <th class="wl-th">Réplicas</th>
              <th class="wl-th">Imagem</th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((w: WorkloadInfo) => (
              <tr
                key={`${w.namespace}/${w.kind}/${w.name}`}
                class={w.status === 'down' ? 'wl-row--down' : w.status === 'degraded' ? 'wl-row--degraded' : ''}
              >
                <td class="wl-td">
                  <div class="wl-kind">
                    <span title={w.kind}>{KIND_ICON[w.kind] ?? '📦'}</span>
                    <span class="wl-kind-label">{w.kind}</span>
                  </div>
                </td>
                <td class="wl-td">
                  <div class="wl-name-cell">
                    <span class="wl-name">{w.name}</span>
                    <span class="wl-ns-badge">{w.namespace}</span>
                  </div>
                </td>
                <td class="wl-td">
                  <span class={statusClass(w.status)}>{statusLabel(w)}</span>
                </td>
                <td class="wl-td wl-image-cell" title={w.image}>{shortImage(w.image)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
