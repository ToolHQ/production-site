import { useState } from 'preact/hooks';
import { useHoneypotRequests } from '../hooks/useHoneypotRequests';
import type { HoneypotFilters } from '../hooks/useHoneypotRequests';

export function ThreatsPanel() {
  const [page, setPage] = useState(0);
  const [filters, setFilters] = useState<HoneypotFilters>({ exclude_internal: true });

  // Temporary state for the filter inputs before hitting "Apply"
  const [tempFilters, setTempFilters] = useState<HoneypotFilters>({ exclude_internal: true });

  const limit = 50;
  const offset = page * limit;

  const { data, error, loading, refresh } = useHoneypotRequests(limit, offset, filters);

  const applyFilters = () => {
    setPage(0); // reset pagination
    setFilters(tempFilters);
  };

  const clearFilters = () => {
    setPage(0);
    const defaults = { exclude_internal: true };
    setTempFilters(defaults);
    setFilters(defaults);
  };

  const formatExactTime = (isoString: string) => {
    const d = new Date(isoString);
    if (isNaN(d.getTime())) return isoString;
    return d.toISOString().replace('T', ' ').replace('Z', '');
  };

  const formatLatency = (val?: number | null) => {
    if (val == null) return '-';
    if (val > 10000) {
      return (val / 1000000).toFixed(2) + 'ms';
    }
    return val.toFixed(2) + 'ms';
  };

  return (
    <section class="panel" style={{ padding: '0', background: 'transparent', boxShadow: 'none' }}>
      <div style={{ background: 'var(--color-bg-default)', borderRadius: '12px', padding: 'var(--space-lg)', boxShadow: '0 8px 24px rgba(0,0,0,0.12)', border: '1px solid var(--color-border-subtle)' }}>
        <div class="section-head" style={{ borderBottom: '1px solid var(--color-border-muted)', paddingBottom: 'var(--space-md)', marginBottom: 'var(--space-md)' }}>
          <div>
            <div class="section-kicker" style={{ color: 'var(--color-accent-blue)', letterSpacing: '1px' }}>HONEYPOT INTEL</div>
            <div class="section-title" style={{ fontSize: '1.5rem', fontWeight: 'bold' }}>Histórico de Ameaças</div>
            <p style={{ color: 'var(--color-fg-muted)' }}>Registro avançado de requisições anômalas e escaneamentos na borda (ClickHouse).</p>
          </div>
          <div class="section-tags">
            <button
              class="dnor-shell__search"
              style={{ background: 'var(--color-bg-overlay)', borderRadius: '20px', padding: '6px 16px', display: 'flex', alignItems: 'center', gap: '8px', border: '1px solid var(--color-border-subtle)', transition: 'all 0.2s ease', cursor: 'pointer' }}
              onClick={refresh}
              disabled={loading}
              aria-label="Atualizar"
            >
              <span style={{ fontSize: '1.2rem', animation: loading ? 'spin 1s linear infinite' : 'none' }}>↻</span>
              <span style={{ fontWeight: 500 }}>{loading ? 'Sincronizando...' : 'Atualizar Dados'}</span>
            </button>
          </div>
        </div>

        <div style={{ background: 'linear-gradient(145deg, var(--color-bg-subtle), var(--color-bg-overlay))', padding: 'var(--space-md)', borderRadius: '8px', marginBottom: 'var(--space-lg)', display: 'flex', gap: 'var(--space-md)', flexWrap: 'wrap', alignItems: 'flex-end', border: '1px solid var(--color-border-muted)', boxShadow: 'inset 0 2px 4px rgba(0,0,0,0.02)' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            <label style={{ fontSize: '0.75rem', fontWeight: 600, color: 'var(--color-fg-muted)', textTransform: 'uppercase', letterSpacing: '0.5px' }}>Método</label>
            <input
              class="dnor-shell__search"
              style={{ width: '90px', padding: '8px 12px', borderRadius: '6px', border: '1px solid var(--color-border-subtle)', background: 'var(--color-bg-default)' }}
              placeholder="GET, POST..."
              value={tempFilters.method || ''}
              onInput={(e) => setTempFilters({...tempFilters, method: (e.target as HTMLInputElement).value})}
            />
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            <label style={{ fontSize: '0.75rem', fontWeight: 600, color: 'var(--color-fg-muted)', textTransform: 'uppercase', letterSpacing: '0.5px' }}>Path</label>
            <input
              class="dnor-shell__search"
              style={{ width: '180px', padding: '8px 12px', borderRadius: '6px', border: '1px solid var(--color-border-subtle)', background: 'var(--color-bg-default)' }}
              placeholder="Ex: /wp-admin"
              value={tempFilters.path || ''}
              onInput={(e) => setTempFilters({...tempFilters, path: (e.target as HTMLInputElement).value})}
            />
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            <label style={{ fontSize: '0.75rem', fontWeight: 600, color: 'var(--color-fg-muted)', textTransform: 'uppercase', letterSpacing: '0.5px' }}>Endereço IP</label>
            <input
              class="dnor-shell__search"
              style={{ width: '140px', padding: '8px 12px', borderRadius: '6px', border: '1px solid var(--color-border-subtle)', background: 'var(--color-bg-default)' }}
              placeholder="Ex: 192.168."
              value={tempFilters.ip || ''}
              onInput={(e) => setTempFilters({...tempFilters, ip: (e.target as HTMLInputElement).value})}
            />
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            <label style={{ fontSize: '0.75rem', fontWeight: 600, color: 'var(--color-fg-muted)', textTransform: 'uppercase', letterSpacing: '0.5px' }}>Classificação</label>
            <select
              class="dnor-shell__search"
              style={{ padding: '8px 12px', borderRadius: '6px', border: '1px solid var(--color-border-subtle)', background: 'var(--color-bg-default)', cursor: 'pointer' }}
              value={tempFilters.classification || ''}
              onChange={(e) => setTempFilters({...tempFilters, classification: (e.target as HTMLSelectElement).value})}
            >
              <option value="">Todas</option>
              <option value="none">Nenhuma (unknown)</option>
              <option value="malicious">Malicious</option>
            </select>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginLeft: 'var(--space-sm)', paddingBottom: '10px' }}>
            <input
              type="checkbox"
              id="exclude_internal"
              checked={tempFilters.exclude_internal || false}
              onChange={(e) => setTempFilters({...tempFilters, exclude_internal: (e.target as HTMLInputElement).checked})}
              style={{ accentColor: 'var(--color-accent-blue)', width: '16px', height: '16px', cursor: 'pointer' }}
            />
            <label htmlFor="exclude_internal" style={{ fontSize: '0.85rem', color: 'var(--color-fg-default)', cursor: 'pointer', userSelect: 'none' }}>
              Ocultar tráfego interno
            </label>
          </div>

          <div style={{ display: 'flex', gap: '12px', marginLeft: 'auto' }}>
            <button
              class="dnor-shell__search"
              style={{ padding: '8px 20px', borderRadius: '6px', background: 'transparent', border: '1px solid var(--color-border-subtle)', color: 'var(--color-fg-default)', fontWeight: 500, cursor: 'pointer', transition: 'background 0.2s ease' }}
              onClick={clearFilters}
              onMouseOver={(e) => e.currentTarget.style.background = 'var(--color-bg-overlay)'}
              onMouseOut={(e) => e.currentTarget.style.background = 'transparent'}
            >
              Limpar
            </button>
            <button
              class="dnor-shell__search"
              style={{ padding: '8px 24px', borderRadius: '6px', background: 'var(--color-accent-blue)', border: 'none', color: '#fff', fontWeight: 600, cursor: 'pointer', boxShadow: '0 4px 12px rgba(0, 112, 243, 0.3)', transition: 'transform 0.1s ease, box-shadow 0.2s ease' }}
              onClick={applyFilters}
              onMouseOver={(e) => { e.currentTarget.style.transform = 'translateY(-1px)'; e.currentTarget.style.boxShadow = '0 6px 16px rgba(0, 112, 243, 0.4)'; }}
              onMouseOut={(e) => { e.currentTarget.style.transform = 'none'; e.currentTarget.style.boxShadow = '0 4px 12px rgba(0, 112, 243, 0.3)'; }}
            >
              Aplicar Filtros
            </button>
          </div>
        </div>

        {error ? (
          <div class="dnor-alert-banner" role="alert" style={{ borderRadius: '8px', borderLeft: '4px solid var(--color-status-red)', background: 'var(--color-bg-overlay)', display: 'flex', gap: '12px', padding: '16px' }}>
            <span class="dnor-alert-banner__icon" aria-hidden="true" style={{ color: 'var(--color-status-red)', fontSize: '1.2rem' }}>⚠</span>
            <p class="dnor-alert-banner__text" style={{ margin: 0, alignSelf: 'center', color: 'var(--color-status-red)' }}>{error}</p>
          </div>
        ) : (
          <div class="table-container" style={{ border: '1px solid var(--color-border-subtle)', borderRadius: '8px', overflow: 'hidden' }}>
            <table class="dnor-table" style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left' }}>
              <thead style={{ background: 'var(--color-bg-subtle)' }}>
                <tr>
                  <th style={{ padding: '12px 16px', fontWeight: 600, color: 'var(--color-fg-muted)', fontSize: '0.85rem', textTransform: 'uppercase', letterSpacing: '0.5px', borderBottom: '2px solid var(--color-border-muted)' }}>Data/Hora</th>
                  <th style={{ padding: '12px 16px', fontWeight: 600, color: 'var(--color-fg-muted)', fontSize: '0.85rem', textTransform: 'uppercase', letterSpacing: '0.5px', borderBottom: '2px solid var(--color-border-muted)' }}>Método</th>
                  <th style={{ padding: '12px 16px', fontWeight: 600, color: 'var(--color-fg-muted)', fontSize: '0.85rem', textTransform: 'uppercase', letterSpacing: '0.5px', borderBottom: '2px solid var(--color-border-muted)' }}>Path</th>
                  <th style={{ padding: '12px 16px', fontWeight: 600, color: 'var(--color-fg-muted)', fontSize: '0.85rem', textTransform: 'uppercase', letterSpacing: '0.5px', borderBottom: '2px solid var(--color-border-muted)' }}>Status</th>
                  <th style={{ padding: '12px 16px', fontWeight: 600, color: 'var(--color-fg-muted)', fontSize: '0.85rem', textTransform: 'uppercase', letterSpacing: '0.5px', borderBottom: '2px solid var(--color-border-muted)' }}>Origem (IP)</th>
                  <th style={{ padding: '12px 16px', fontWeight: 600, color: 'var(--color-fg-muted)', fontSize: '0.85rem', textTransform: 'uppercase', letterSpacing: '0.5px', borderBottom: '2px solid var(--color-border-muted)' }}>User-Agent</th>
                  <th style={{ padding: '12px 16px', fontWeight: 600, color: 'var(--color-fg-muted)', fontSize: '0.85rem', textTransform: 'uppercase', letterSpacing: '0.5px', borderBottom: '2px solid var(--color-border-muted)' }}>Latência</th>
                  <th style={{ padding: '12px 16px', fontWeight: 600, color: 'var(--color-fg-muted)', fontSize: '0.85rem', textTransform: 'uppercase', letterSpacing: '0.5px', borderBottom: '2px solid var(--color-border-muted)' }}>Tag</th>
                </tr>
              </thead>
              <tbody>
                {!data && loading && (
                  <tr>
                    <td colSpan={8} style={{ textAlign: 'center', padding: '40px', color: 'var(--color-fg-muted)' }}>
                      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '12px' }}>
                        <div style={{ fontSize: '2rem', animation: 'spin 1s linear infinite' }}>↻</div>
                        <div>Carregando registros do banco de dados...</div>
                      </div>
                    </td>
                  </tr>
                )}
                {data && data.rows.length === 0 && (
                  <tr>
                    <td colSpan={8} style={{ textAlign: 'center', padding: '40px', color: 'var(--color-fg-muted)' }}>
                      <div style={{ fontSize: '1.1rem', marginBottom: '8px' }}>Nenhum registro encontrado</div>
                      <div style={{ fontSize: '0.9rem' }}>Modifique os filtros ou tente novamente mais tarde.</div>
                    </td>
                  </tr>
                )}
                {data && data.rows.map((row) => (
                  <tr key={row.id} style={{ borderBottom: '1px solid var(--color-border-subtle)', transition: 'background 0.15s ease' }} onMouseOver={(e) => e.currentTarget.style.background = 'var(--color-bg-subtle)'} onMouseOut={(e) => e.currentTarget.style.background = 'transparent'}>
                    <td style={{ padding: '12px 16px', fontFamily: 'var(--font-mono)', fontSize: '0.85em', whiteSpace: 'nowrap', color: 'var(--color-fg-muted)' }}>
                      {formatExactTime(row.timestamp)}
                    </td>
                    <td style={{ padding: '12px 16px' }}>
                      <span class={`dnor-badge ${row.method === 'GET' ? 'dnor-badge--green' : row.method === 'POST' ? 'dnor-badge--blue' : 'dnor-badge--gray'}`} style={{ padding: '2px 8px', borderRadius: '4px', fontWeight: 600, fontSize: '0.75rem' }}>
                        {row.method}
                      </span>
                    </td>
                    <td style={{ padding: '12px 16px', fontFamily: 'var(--font-mono)', fontSize: '0.9em', maxWidth: '250px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={row.path}>
                      {row.path}
                    </td>
                    <td style={{ padding: '12px 16px', fontFamily: 'var(--font-mono)', fontSize: '0.9em', color: row.statusCode >= 400 ? 'var(--color-status-red)' : 'var(--color-fg-default)' }}>
                      {row.statusCode}
                    </td>
                    <td style={{ padding: '12px 16px', fontFamily: 'var(--font-mono)', fontSize: '0.9em' }}>
                      <span style={{ color: 'var(--color-accent-blue)' }}>{row.remoteIp || '-'}</span> {row.country ? <span style={{ color: 'var(--color-fg-muted)', fontSize: '0.85em' }}>({row.country})</span> : ''}
                    </td>
                    <td style={{ padding: '12px 16px', fontSize: '0.85em', color: 'var(--color-fg-muted)', maxWidth: '180px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={row.userAgent || ''}>
                      {row.userAgent || '-'}
                    </td>
                    <td style={{ padding: '12px 16px', fontFamily: 'var(--font-mono)', fontSize: '0.85em', color: 'var(--color-fg-muted)' }}>
                      {formatLatency(row.timeElapsed ?? undefined)}
                    </td>
                    <td style={{ padding: '12px 16px' }}>
                      {row.classification && row.classification !== 'unknown' ? (
                        <span class={`dnor-badge ${row.classification === 'malicious' ? 'dnor-badge--red' : 'dnor-badge--yellow'}`} style={{ padding: '2px 8px', borderRadius: '4px', textTransform: 'capitalize' }}>
                          {row.classification}
                        </span>
                      ) : (
                        <span class="dnor-badge dnor-badge--gray" style={{ padding: '2px 8px', borderRadius: '4px' }}>Desconhecida</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            {data && (
              <div style={{ background: 'var(--color-bg-subtle)', padding: '12px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderTop: '1px solid var(--color-border-muted)' }}>
                <span style={{ fontSize: '0.9rem', color: 'var(--color-fg-muted)' }}>
                  Exibindo registros <strong style={{ color: 'var(--color-fg-default)' }}>{data.total > 0 ? offset + 1 : 0} - {Math.min(offset + limit, data.total)}</strong> de <strong style={{ color: 'var(--color-fg-default)' }}>{data.total}</strong>
                </span>
                <div style={{ display: 'flex', gap: '8px' }}>
                  <button
                    class="dnor-shell__search"
                    disabled={page === 0 || loading}
                    onClick={() => setPage(p => Math.max(0, p - 1))}
                    style={{ padding: '6px 16px', borderRadius: '6px', background: page === 0 ? 'var(--color-bg-overlay)' : 'var(--color-bg-default)', border: '1px solid var(--color-border-subtle)', cursor: page === 0 ? 'not-allowed' : 'pointer', opacity: page === 0 ? 0.5 : 1 }}
                  >
                    &laquo; Anterior
                  </button>
                  <button
                    class="dnor-shell__search"
                    disabled={offset + limit >= data.total || loading}
                    onClick={() => setPage(p => p + 1)}
                    style={{ padding: '6px 16px', borderRadius: '6px', background: offset + limit >= data.total ? 'var(--color-bg-overlay)' : 'var(--color-bg-default)', border: '1px solid var(--color-border-subtle)', cursor: offset + limit >= data.total ? 'not-allowed' : 'pointer', opacity: offset + limit >= data.total ? 0.5 : 1 }}
                  >
                    Próxima &raquo;
                  </button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </section>
  );
}
