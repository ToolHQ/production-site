import type { NamespacesData, NamespaceQuota } from '../types/api';

interface NamespacePanelProps {
  data: NamespacesData | null;
  error: string | null;
}

function pressureClass(pct: number): string {
  if (pct > 80) return 'ns-bar ns-bar--critical';
  if (pct > 50) return 'ns-bar ns-bar--warning';
  return 'ns-bar ns-bar--ok';
}

function pressureLabelClass(pct: number): string {
  if (pct > 80) return 'ns-pct ns-pct--critical';
  if (pct > 50) return 'ns-pct ns-pct--warning';
  return 'ns-pct ns-pct--ok';
}

function rowClass(ns: NamespaceQuota): string {
  const max = Math.max(ns.cpu_pressure_pct, ns.mem_pressure_pct);
  if (max > 80) return 'ns-row ns-row--critical';
  if (max > 50) return 'ns-row ns-row--warning';
  return 'ns-row';
}

function PressureBar({ pct }: { pct: number }) {
  const clamped = Math.max(0, Math.min(100, pct));
  return (
    <div class="ns-bar-wrap" title={`${pct}%`}>
      <div class={pressureClass(pct)} style={{ width: `${clamped}%` }} />
      <span class={pressureLabelClass(pct)}>{pct.toFixed(0)}%</span>
    </div>
  );
}

export function NamespacePanel({ data, error }: NamespacePanelProps) {
  if (error && !data) {
    return (
      <div class="panel panel--error">
        <h2 class="panel-title">📊 Quotas de Namespaces</h2>
        <p class="panel-error">{error}</p>
      </div>
    );
  }

  if (!data) {
    return (
      <div class="panel panel--loading">
        <h2 class="panel-title">📊 Quotas de Namespaces</h2>
        <p class="panel-loading">Carregando…</p>
      </div>
    );
  }

  if (data.total === 0) {
    return (
      <div class="panel">
        <div class="panel-header">
          <h2 class="panel-title">📊 Quotas de Namespaces</h2>
          <span class="summary-badge summary-badge--neutral">Sem quotas configuradas</span>
        </div>
        <p class="panel-loading">Nenhum ResourceQuota encontrado no cluster.</p>
      </div>
    );
  }

  // Sort by max pressure descending (most loaded first)
  const sorted = [...data.namespaces].sort((a, b) => {
    const pa = Math.max(a.cpu_pressure_pct, a.mem_pressure_pct);
    const pb = Math.max(b.cpu_pressure_pct, b.mem_pressure_pct);
    return pb - pa;
  });

  return (
    <div class="panel">
      <div class="panel-header">
        <h2 class="panel-title">📊 Quotas de Namespaces</h2>
        <div class="panel-summary">
          {data.over_pressure > 0 && (
            <span class="summary-badge summary-badge--error">
              {data.over_pressure} sob pressão
            </span>
          )}
          <span class="summary-badge summary-badge--neutral">
            {data.total} namespace{data.total > 1 ? 's' : ''}
          </span>
        </div>
      </div>

      {error && <p class="panel-inline-warn">⚠ {error}</p>}

      <div class="panel-table-wrap">
        <table class="panel-table">
          <thead>
            <tr>
              <th>Namespace</th>
              <th>CPU usado / limite</th>
              <th>% CPU</th>
              <th>Mem usada / limite</th>
              <th>% Mem</th>
              <th>Pods</th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((ns: NamespaceQuota) => (
              <tr key={ns.name} class={rowClass(ns)}>
                <td class="ns-name">{ns.name}</td>
                <td class="ns-quota">
                  <span class="ns-used">{ns.cpu_limit_used}</span>
                  <span class="ns-sep">/</span>
                  <span class="ns-limit">{ns.cpu_limit_limit}</span>
                </td>
                <td class="ns-bar-cell">
                  <PressureBar pct={ns.cpu_pressure_pct} />
                </td>
                <td class="ns-quota">
                  <span class="ns-used">{ns.mem_limit_used}</span>
                  <span class="ns-sep">/</span>
                  <span class="ns-limit">{ns.mem_limit_limit}</span>
                </td>
                <td class="ns-bar-cell">
                  <PressureBar pct={ns.mem_pressure_pct} />
                </td>
                <td class="ns-pods">
                  {ns.pods_limit > 0 ? `${ns.pods_used}/${ns.pods_limit}` : ns.pods_used}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
