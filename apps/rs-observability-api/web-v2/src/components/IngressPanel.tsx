import type { IngressesData, IngressInfo } from '../types/api';

interface IngressPanelProps {
  data: IngressesData | null;
  error: string | null;
}

export function IngressPanel({ data, error }: IngressPanelProps) {
  if (error && !data) {
    return (
      <div class="panel panel--error">
        <h2 class="panel-title">🌐 Ingresses</h2>
        <p class="panel-error">{error}</p>
      </div>
    );
  }

  if (!data) {
    return (
      <div class="panel panel--loading">
        <h2 class="panel-title">🌐 Ingresses</h2>
        <p class="panel-loading">Carregando…</p>
      </div>
    );
  }

  const sorted = [...data.ingresses].sort((a, b) =>
    a.namespace.localeCompare(b.namespace) || a.name.localeCompare(b.name)
  );

  return (
    <div class="panel">
      <div class="panel-header">
        <h2 class="panel-title">🌐 Ingresses</h2>
        <div class="panel-summary">
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
              <th>Hosts</th>
              <th>TLS</th>
              <th>Classe</th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((ing: IngressInfo) => (
              <tr key={`${ing.namespace}/${ing.name}`}>
                <td class="ing-name">{ing.name}</td>
                <td class="ing-ns">{ing.namespace}</td>
                <td class="ing-hosts">
                  {ing.hosts.map((h) => (
                    <a
                      key={h}
                      href={`https://${h}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="ing-host-link"
                    >
                      {h}
                    </a>
                  ))}
                  {ing.hosts.length === 0 && <span class="ing-no-host">—</span>}
                </td>
                <td>
                  {ing.tls ? (
                    <span class="tls-badge tls-badge--on" title={ing.tls_secret ?? ''}>
                      🔒 TLS
                    </span>
                  ) : (
                    <span class="tls-badge tls-badge--off">HTTP</span>
                  )}
                </td>
                <td class="ing-class">{ing.class ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
