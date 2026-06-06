import { useState } from 'preact/hooks';
import { useHoneypotRequests } from '../hooks/useHoneypotRequests';
import type { HoneypotFilters } from '../hooks/useHoneypotRequests';

export function ThreatsPanel() {
  const [page, setPage] = useState(0);
  const [filters, setFilters] = useState<HoneypotFilters>({});
  
  // Temporary state for the filter inputs before hitting "Apply"
  const [tempFilters, setTempFilters] = useState<HoneypotFilters>({});

  const limit = 50;
  const offset = page * limit;
  
  const { data, error, loading, refresh } = useHoneypotRequests(limit, offset, filters);

  const applyFilters = () => {
    setPage(0); // reset pagination
    setFilters(tempFilters);
  };

  const clearFilters = () => {
    setPage(0);
    setTempFilters({});
    setFilters({});
  };

  const formatExactTime = (isoString: string) => {
    const d = new Date(isoString);
    if (isNaN(d.getTime())) return isoString;
    return d.toISOString().replace('T', ' ').replace('Z', '');
  };

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

      <div style={{ background: 'var(--color-bg-subtle)', padding: 'var(--space-md)', borderRadius: '6px', marginBottom: 'var(--space-md)', display: 'flex', gap: 'var(--space-sm)', flexWrap: 'wrap', alignItems: 'flex-end' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
          <label style={{ fontSize: '0.8rem', color: 'var(--color-fg-muted)' }}>Método</label>
          <input 
            class="dnor-shell__search" 
            style={{ width: '80px', padding: '4px 8px' }} 
            placeholder="Ex: POST" 
            value={tempFilters.method || ''} 
            onInput={(e) => setTempFilters({...tempFilters, method: (e.target as HTMLInputElement).value})}
          />
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
          <label style={{ fontSize: '0.8rem', color: 'var(--color-fg-muted)' }}>Path</label>
          <input 
            class="dnor-shell__search" 
            style={{ width: '150px', padding: '4px 8px' }} 
            placeholder="Ex: /wp-admin" 
            value={tempFilters.path || ''} 
            onInput={(e) => setTempFilters({...tempFilters, path: (e.target as HTMLInputElement).value})}
          />
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
          <label style={{ fontSize: '0.8rem', color: 'var(--color-fg-muted)' }}>IP</label>
          <input 
            class="dnor-shell__search" 
            style={{ width: '120px', padding: '4px 8px' }} 
            placeholder="Ex: 192.168." 
            value={tempFilters.ip || ''} 
            onInput={(e) => setTempFilters({...tempFilters, ip: (e.target as HTMLInputElement).value})}
          />
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
          <label style={{ fontSize: '0.8rem', color: 'var(--color-fg-muted)' }}>Classificação</label>
          <select 
            class="dnor-shell__search" 
            style={{ padding: '4px 8px', background: 'transparent' }} 
            value={tempFilters.classification || ''} 
            onChange={(e) => setTempFilters({...tempFilters, classification: (e.target as HTMLSelectElement).value})}
          >
            <option value="">Todas</option>
            <option value="none">Nenhuma (unknown)</option>
            <option value="internal-route">Internal Route</option>
            <option value="malicious">Malicious</option>
          </select>
        </div>
        <div style={{ display: 'flex', gap: '8px', marginLeft: 'auto' }}>
          <button class="dnor-shell__search" style={{ padding: '4px 12px', background: 'var(--color-bg-overlay)' }} onClick={clearFilters}>Limpar</button>
          <button class="dnor-shell__search" style={{ padding: '4px 12px', background: 'var(--color-fg-default)', color: 'var(--color-bg-default)' }} onClick={applyFilters}>Filtrar</button>
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
                <th>User-Agent</th>
                <th>Latência</th>
                <th>Classificação</th>
              </tr>
            </thead>
            <tbody>
              {!data && loading && (
                <tr>
                  <td colSpan={8} style={{ textAlign: 'center', padding: 'var(--space-md)' }}>
                    Buscando registros...
                  </td>
                </tr>
              )}
              {data && data.rows.length === 0 && (
                <tr>
                  <td colSpan={8} style={{ textAlign: 'center', padding: 'var(--space-md)', color: 'var(--color-fg-muted)' }}>
                    Nenhum registro encontrado para os filtros atuais.
                  </td>
                </tr>
              )}
              {data && data.rows.map((row) => (
                <tr key={row.id}>
                  <td style={{ fontFamily: 'var(--font-mono)', fontSize: '0.85em', whiteSpace: 'nowrap' }}>
                    {formatExactTime(row.timestamp)}
                  </td>
                  <td>
                    <span class={`dnor-badge ${row.method === 'GET' ? 'dnor-badge--green' : row.method === 'POST' ? 'dnor-badge--blue' : 'dnor-badge--gray'}`}>
                      {row.method}
                    </span>
                  </td>
                  <td style={{ fontFamily: 'var(--font-mono)', fontSize: '0.9em', maxWidth: '200px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={row.path}>
                    {row.path}
                  </td>
                  <td>{row.statusCode}</td>
                  <td style={{ fontFamily: 'var(--font-mono)', fontSize: '0.9em' }}>
                    {row.remoteIp || '-'} {row.country ? `(${row.country})` : ''}
                  </td>
                  <td style={{ fontSize: '0.85em', color: 'var(--color-fg-muted)', maxWidth: '150px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={row.userAgent || ''}>
                    {row.userAgent || '-'}
                  </td>
                  <td style={{ fontFamily: 'var(--font-mono)', fontSize: '0.9em' }}>
                    {row.timeElapsed != null ? `${row.timeElapsed.toFixed(2)}ms` : '-'}
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
                Mostrando {data.total > 0 ? offset + 1 : 0} - {Math.min(offset + limit, data.total)} de {data.total}
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
