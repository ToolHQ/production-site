import { useState } from 'preact/hooks';
import { useHoneypotRequests } from '../hooks/useHoneypotRequests';
import { formatRelativeTime } from '../utils/format';

export function ThreatsPanel() {
  const [page, setPage] = useState(0);
  const limit = 50;
  const offset = page * limit;
  
  const { data, error, loading, refresh } = useHoneypotRequests(limit, offset);

  return (
    <section class="panel">
      <div class="section-head">
        <div>
          <div class="section-kicker">Honeypot</div>
          <div class="section-title">Histórico de Ameaças</div>
          <p>Registro completo de requisições interceptadas pela borda na AWS EC2.</p>
        </div>
        <div class="section-tags">
          <button class="dnor-shell__search" onClick={refresh} disabled={loading} aria-label="Atualizar">
            {loading ? 'Carregando...' : '↻ Atualizar'}
          </button>
        </div>
      </div>

      {error ? (
        <div class="dnor-alert-banner" role="alert">
          <span class="dnor-alert-banner__icon" aria-hidden="true">⚠</span>
          <p class="dnor-alert-banner__text">{error}</p>
        </div>
      ) : (
        <div class="table-container">
          <table class="dnor-table">
            <thead>
              <tr>
                <th>Data</th>
                <th>Método</th>
                <th>Path</th>
                <th>Status</th>
                <th>IP</th>
                <th>Classificação</th>
              </tr>
            </thead>
            <tbody>
              {!data && loading && (
                <tr>
                  <td colSpan={6} style={{ textAlign: 'center', padding: 'var(--space-md)' }}>
                    Buscando registros...
                  </td>
                </tr>
              )}
              {data && data.rows.length === 0 && (
                <tr>
                  <td colSpan={6} style={{ textAlign: 'center', padding: 'var(--space-md)', color: 'var(--color-fg-muted)' }}>
                    Nenhum registro encontrado.
                  </td>
                </tr>
              )}
              {data && data.rows.map((row) => (
                <tr key={row.id}>
                  <td title={row.timestamp}>{formatRelativeTime(row.timestamp)}</td>
                  <td>
                    <span class={`dnor-badge ${row.method === 'GET' ? 'dnor-badge--green' : row.method === 'POST' ? 'dnor-badge--blue' : 'dnor-badge--gray'}`}>
                      {row.method}
                    </span>
                  </td>
                  <td style={{ fontFamily: 'var(--font-mono)', fontSize: '0.9em', maxWidth: '300px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={row.path}>
                    {row.path}
                  </td>
                  <td>{row.statusCode}</td>
                  <td>
                    {row.remoteIp || '-'} {row.country ? `(${row.country})` : ''}
                  </td>
                  <td>
                    {row.classification ? (
                      <span class={`dnor-badge ${row.classification === 'malicious' ? 'dnor-badge--red' : 'dnor-badge--yellow'}`}>
                        {row.classification}
                      </span>
                    ) : (
                      <span class="dnor-badge dnor-badge--gray">unknown</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          {data && (
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 'var(--space-md)' }}>
              <span style={{ fontSize: '0.9rem', color: 'var(--color-fg-muted)' }}>
                Mostrando {offset + 1} - {Math.min(offset + limit, data.total)} de {data.total}
              </span>
              <div style={{ display: 'flex', gap: 'var(--space-sm)' }}>
                <button 
                  class="dnor-shell__search" 
                  disabled={page === 0 || loading} 
                  onClick={() => setPage(p => Math.max(0, p - 1))}
                  style={{ padding: '4px 12px' }}
                >
                  &laquo; Anterior
                </button>
                <button 
                  class="dnor-shell__search" 
                  disabled={offset + limit >= data.total || loading} 
                  onClick={() => setPage(p => p + 1)}
                  style={{ padding: '4px 12px' }}
                >
                  Próxima &raquo;
                </button>
              </div>
            </div>
          )}
        </div>
      )}
    </section>
  );
}
