import type { LonghornData, LonghornVolume, LonghornNodeCapacity } from '../types/api';

interface StoragePanelProps {
  data: LonghornData | null;
  error: string | null;
}

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const units = ['B', 'Ki', 'Mi', 'Gi', 'Ti'];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  const val = bytes / Math.pow(1024, i);
  return `${val % 1 === 0 ? val : val.toFixed(1)} ${units[i]}`;
}

function robustnessBadge(r: string): string {
  if (r === 'healthy') return 'storage-badge storage-badge--healthy';
  if (r === 'degraded') return 'storage-badge storage-badge--degraded';
  if (r === 'faulted') return 'storage-badge storage-badge--faulted';
  return 'storage-badge storage-badge--unknown';
}

function stateLabel(s: string): string {
  if (s === 'attached') return '⬤ attached';
  if (s === 'detached') return '○ detached';
  return s;
}

function VolumeRow({ vol }: { vol: LonghornVolume }) {
  const usePct =
    vol.size_bytes > 0 ? Math.round((vol.actual_size_bytes / vol.size_bytes) * 100) : 0;
  const usePctCapped = Math.min(usePct, 100);
  const useClass =
    usePct > 90 ? 'storage-use storage-use--critical'
    : usePct > 75 ? 'storage-use storage-use--warn'
    : 'storage-use';
  return (
    <tr class="storage-row">
      <td class="storage-cell storage-cell--name" title={vol.name}>
        <span class="storage-pvc">{vol.pvc_name}</span>
        <span class="storage-ns">{vol.namespace}</span>
      </td>
      <td class="storage-cell">
        <span class={robustnessBadge(vol.robustness)}>{vol.robustness}</span>
      </td>
      <td class="storage-cell storage-cell--state">
        <span class={`storage-state${vol.state === 'attached' ? ' storage-state--attached' : ''}`}>
          {stateLabel(vol.state)}
        </span>
      </td>
      <td class="storage-cell storage-cell--size">
        <span class="storage-size">{formatBytes(vol.size_bytes)}</span>
        <div class="storage-use-bar-wrap" title={`${usePct}% usado`}>
          <div class="storage-use-bar" style={{ width: `${usePctCapped}%` }} />
        </div>
        <span class={useClass}>{usePct}% usado</span>
      </td>
      <td class="storage-cell storage-cell--replicas">{vol.replicas_desired}×</td>
      <td class="storage-cell storage-cell--node" title={vol.node}>
        {vol.node ? vol.node.replace('k8s-', '') : '—'}
      </td>
    </tr>
  );
}

function NodeCapacityRow({ node }: { node: LonghornNodeCapacity }) {
  const schedulableClass = node.schedulable
    ? 'storage-badge storage-badge--healthy'
    : 'storage-badge storage-badge--faulted';
  const schedulableLabel = node.schedulable ? 'Schedulable' : 'Disabled';

  const usageBytes = node.storage_maximum - node.storage_available;
  const usePct = node.storage_maximum > 0 ? Math.round((usageBytes / node.storage_maximum) * 100) : 0;
  const usePctCapped = Math.min(usePct, 100);

  // Alertas de Headroom (Espaço Disponível/Livre):
  // Vermelho se < 10 GiB (10737418240 bytes)
  // Amarelo se < 15 GiB (16106127360 bytes)
  // Verde se >= 15 GiB
  const GIB = 1024 * 1024 * 1024;
  const headroomClass =
    node.storage_available < 10 * GIB ? 'storage-use storage-use--critical'
    : node.storage_available < 15 * GIB ? 'storage-use storage-use--warn'
    : 'storage-use';

  return (
    <tr class="storage-row">
      <td class="storage-cell storage-cell--name">
        <span class="storage-pvc">{node.name.replace('k8s-', '')}</span>
      </td>
      <td class="storage-cell">
        <span class={schedulableClass}>{schedulableLabel}</span>
      </td>
      <td class="storage-cell">
        <span class="storage-size">{formatBytes(node.storage_maximum)}</span>
      </td>
      <td class="storage-cell">
        <span class="storage-size">{formatBytes(node.storage_scheduled)}</span>
        <div class="storage-use-bar-wrap" title={`${Math.round((node.storage_scheduled / node.storage_maximum) * 100)}% alocado`}>
          <div class="storage-use-bar" style={{ width: `${Math.min(Math.round((node.storage_scheduled / node.storage_maximum) * 100), 100)}%`, backgroundColor: '#3498db' }} />
        </div>
      </td>
      <td class="storage-cell">
        <span class="storage-size" style={{ fontWeight: 'bold' }}>{formatBytes(node.storage_available)}</span>
        <div class="storage-use-bar-wrap" title={`${usePct}% usado`}>
          <div
            class="storage-use-bar"
            style={{
              width: `${usePctCapped}%`,
              backgroundColor: node.storage_available < 10 * GIB ? '#ef4444' : node.storage_available < 15 * GIB ? '#f59e0b' : '#10b981'
            }}
          />
        </div>
        <span class={headroomClass}>
          {node.storage_available < 10 * GIB ? '🚨 Crítico (<10G)' : node.storage_available < 15 * GIB ? '⚠️ Baixo (<15G)' : '🟢 Saudável'}
        </span>
      </td>
    </tr>
  );
}

export function StoragePanel({ data, error }: StoragePanelProps) {
  if (!data && error) {
    return (
      <section class="storage-panel storage-panel--error">
        <h2 class="storage-panel-title">💾 Storage — Longhorn</h2>
        <p class="storage-error">{error}</p>
      </section>
    );
  }

  if (!data) {
    return (
      <section class="storage-panel storage-panel--loading">
        <h2 class="storage-panel-title">💾 Storage — Longhorn</h2>
        <p class="storage-loading">Carregando volumes…</p>
      </section>
    );
  }

  if (!data.available) {
    return (
      <section class="storage-panel storage-panel--offline">
        <h2 class="storage-panel-title">💾 Storage — Longhorn</h2>
        <p class="storage-error">{data.error ?? 'K8s API indisponível'}</p>
      </section>
    );
  }

  const summaryTone =
    data.faulted > 0
      ? 'storage-summary--faulted'
      : data.degraded > 0
        ? 'storage-summary--degraded'
        : 'storage-summary--healthy';

  const sorted = [...data.volumes].sort((a, b) => {
    const order = { faulted: 0, degraded: 1, healthy: 2 };
    const ao = order[a.robustness as keyof typeof order] ?? 3;
    const bo = order[b.robustness as keyof typeof order] ?? 3;
    return ao !== bo ? ao - bo : a.pvc_name.localeCompare(b.pvc_name);
  });

  return (
    <section class="storage-panel">
      <div class="storage-header">
        <h2 class="storage-panel-title">💾 Storage — Longhorn</h2>
        <div class={`storage-summary ${summaryTone}`}>
          <span class="storage-summary-item storage-summary--ok">{data.healthy} healthy</span>
          {data.degraded > 0 && (
            <span class="storage-summary-item storage-summary--warn">
              {data.degraded} degraded
            </span>
          )}
          {data.faulted > 0 && (
            <span class="storage-summary-item storage-summary--crit">{data.faulted} faulted</span>
          )}
          <span class="storage-summary-total">{data.total} volumes</span>
        </div>
      </div>
      <div class="storage-table-wrap">
        <table class="storage-table">
          <thead>
            <tr>
              <th class="storage-th">PVC / Namespace</th>
              <th class="storage-th">Robustness</th>
              <th class="storage-th">Estado</th>
              <th class="storage-th">Capacidade</th>
              <th class="storage-th">Réplicas</th>
              <th class="storage-th">Nó</th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((vol) => (
              <VolumeRow key={vol.name} vol={vol} />
            ))}
          </tbody>
        </table>
      </div>

      {data.nodes_capacity && data.nodes_capacity.length > 0 && (
        <div class="storage-nodes-wrap" style={{ marginTop: '24px' }}>
          <h3 class="storage-sub-title" style={{ fontSize: '1.1rem', fontWeight: 600, color: 'var(--text-primary)', marginBottom: '12px', display: 'flex', alignItems: 'center', gap: '8px' }}>
            🖥️ Capacidade Física e Headroom dos Nós
          </h3>
          <div class="storage-table-wrap">
            <table class="storage-table">
              <thead>
                <tr>
                  <th class="storage-th">Nó</th>
                  <th class="storage-th">Agendável</th>
                  <th class="storage-th">Capacidade Total</th>
                  <th class="storage-th">Alocado (Scheduled)</th>
                  <th class="storage-th">Headroom Disponível (Livre)</th>
                </tr>
              </thead>
              <tbody>
                {data.nodes_capacity.map((node) => (
                  <NodeCapacityRow key={node.name} node={node} />
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </section>
  );
}
