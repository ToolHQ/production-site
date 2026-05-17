import type { CertificatesData, CertInfo } from '../types/api';

interface CertExpiryPanelProps {
  data: CertificatesData | null;
  error: string | null;
}

function daysClass(days: number | null): string {
  if (days === null) return 'cert-days cert-days--unknown';
  if (days < 14) return 'cert-days cert-days--critical';
  if (days < 60) return 'cert-days cert-days--warning';
  return 'cert-days cert-days--ok';
}

function daysLabel(days: number | null): string {
  if (days === null) return '?';
  if (days < 0) return 'Expirado';
  return `${days}d`;
}

function daysIcon(days: number | null): string {
  if (days === null) return '❓';
  if (days < 0) return '💀';
  if (days < 14) return '🔴';
  if (days < 60) return '🟡';
  return '🟢';
}

export function CertExpiryPanel({ data, error }: CertExpiryPanelProps) {
  if (error && !data) {
    return (
      <div class="panel panel--error">
        <h2 class="panel-title">🔐 Certificados TLS</h2>
        <p class="panel-error">{error}</p>
      </div>
    );
  }

  if (!data) {
    return (
      <div class="panel panel--loading">
        <h2 class="panel-title">🔐 Certificados TLS</h2>
        <p class="panel-loading">Carregando…</p>
      </div>
    );
  }

  // Sort: critical first, then warning, then ok
  const sorted = [...data.certificates].sort((a, b) => {
    const da = a.days_remaining ?? 999999;
    const db = b.days_remaining ?? 999999;
    return da - db;
  });

  return (
    <div class="panel">
      <div class="panel-header">
        <h2 class="panel-title">🔐 Certificados TLS</h2>
        <div class="panel-summary">
          {data.critical > 0 && (
            <span class="summary-badge summary-badge--error">
              {data.critical} crítico{data.critical > 1 ? 's' : ''}
            </span>
          )}
          {data.expiring_soon > 0 && (
            <span class="summary-badge summary-badge--warn">
              {data.expiring_soon} expirando
            </span>
          )}
          <span class="summary-badge summary-badge--ok">
            {data.total - data.expiring_soon} ok
          </span>
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
              <th>Domínios</th>
              <th>Expira em</th>
              <th>Ready</th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((cert: CertInfo) => (
              <tr key={`${cert.namespace}/${cert.name}`}>
                <td class="cert-name">{cert.name}</td>
                <td class="cert-ns">{cert.namespace}</td>
                <td class="cert-domains">
                  {cert.dns_names.slice(0, 2).join(', ')}
                  {cert.dns_names.length > 2 && ` +${cert.dns_names.length - 2}`}
                </td>
                <td>
                  <span class={daysClass(cert.days_remaining)}>
                    {daysIcon(cert.days_remaining)} {daysLabel(cert.days_remaining)}
                  </span>
                </td>
                <td class="cert-ready">
                  {cert.ready ? (
                    <span class="cert-ready-badge cert-ready-badge--ok">✓</span>
                  ) : (
                    <span class="cert-ready-badge cert-ready-badge--no">✗</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
