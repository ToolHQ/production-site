import type { ComponentChildren } from 'preact';
import { useEffect, useMemo, useState } from 'preact/hooks';
import { MetricSparkline } from './MetricSparkline';
import { clusterBadgeClass } from '../utils/clusterBadge';
import type { FleetOverviewRow, FleetPeriod, FleetStatus } from '../utils/fleetOverview';
import { fleetActivityMetrics } from '../utils/fleetOverview';

interface FleetOverviewTableProps {
  rows: FleetOverviewRow[];
  period?: FleetPeriod;
  highlight?: (text: string, query: string) => ComponentChildren;
  query?: string;
  pageSize?: number;
}

const DEFAULT_PAGE_SIZE = 8;

function statusLabel(status: FleetStatus): string {
  switch (status) {
    case 'honeypot':
      return 'Honeypot';
    case 'online':
      return 'Online';
    case 'degraded':
      return 'Degraded';
    case 'offline':
      return 'Offline';
  }
}

function MetricCell({
  value,
  series,
  color,
}: {
  value: number | null;
  series: FleetOverviewRow['requests24h'];
  color: string;
}) {
  if (value === null) {
    return <span class="fleet-metric-empty">—</span>;
  }

  return (
    <div class="fleet-metric-cell">
      <span class="fleet-metric-value">{value.toLocaleString()}</span>
      {series.length >= 2 && (
        <MetricSparkline points={series} color={color} width={88} height={24} />
      )}
    </div>
  );
}

export function FleetOverviewTable({
  rows,
  period = '24h',
  highlight,
  query = '',
  pageSize = DEFAULT_PAGE_SIZE,
}: FleetOverviewTableProps) {
  const [page, setPage] = useState(1);

  const totalPages = Math.max(1, Math.ceil(rows.length / pageSize));
  const safePage = Math.min(page, totalPages);
  const pageRows = useMemo(() => {
    const start = (safePage - 1) * pageSize;
    return rows.slice(start, start + pageSize);
  }, [rows, safePage, pageSize]);

  useEffect(() => {
    setPage(1);
  }, [rows.length, query]);

  if (rows.length === 0) return null;

  const activityHeader = period === '7d' ? 'Last 7D' : 'Last 24H';
  const hl = (text: string) => (highlight ? highlight(text, query) : text);

  return (
    <section class="fleet-overview">
      <div class="fleet-overview__header">
        <div>
          <h3 class="fleet-overview__title">Fleet overview</h3>
          <p class="fleet-overview__subtitle">
            Showing {(safePage - 1) * pageSize + 1}–{Math.min(safePage * pageSize, rows.length)} of {rows.length} nodes
          </p>
        </div>
      </div>

      <div class="table-shell fleet-overview__shell">
        <table class="fleet-table">
          <thead>
            <tr>
              <th>Status</th>
              <th>Node</th>
              <th>Environment</th>
              <th>IP</th>
              <th>ASN</th>
              <th>Total Requests</th>
              <th>{activityHeader}</th>
              <th>Classified</th>
              <th class="fleet-table__actions-col">Actions</th>
            </tr>
          </thead>
          <tbody>
            {pageRows.map((row) => {
              const activity = fleetActivityMetrics(row, period);
              return (
              <tr
                key={row.key}
                class={`fleet-row fleet-row--${row.status}${row.isHoneypot ? ' fleet-row--honeypot' : ''}`}
              >
                <td class="fleet-status-cell">
                  <span
                    class={`fleet-status-dot fleet-status-dot--${row.status}`}
                    title={statusLabel(row.status)}
                    aria-label={statusLabel(row.status)}
                  />
                </td>
                <td class="fleet-node-cell">
                  <span class="fleet-node-name">{hl(row.name)}</span>
                  {row.subtitle && row.subtitle !== row.name && (
                    <span class="fleet-node-sub">{hl(row.subtitle)}</span>
                  )}
                </td>
                <td>
                  <span class={`node-cluster-badge ${clusterBadgeClass(row.cluster)}`}>
                    {row.cluster}
                  </span>
                </td>
                <td class="fleet-ip-cell">
                  <code>{hl(row.ip)}</code>
                </td>
                <td class="fleet-asn-cell">
                  <span class="fleet-asn-code">{row.asn}</span>
                  <span class="fleet-asn-label">{row.asnLabel}</span>
                </td>
                <td>
                  <MetricCell
                    value={row.totalRequests}
                    series={row.requests7d}
                    color="#ff9900"
                  />
                </td>
                <td>
                  <MetricCell
                    value={activity.value}
                    series={activity.series}
                    color="#ffb347"
                  />
                </td>
                <td class="fleet-classified-cell">
                  {row.classified === null ? (
                    <span class="fleet-metric-empty">—</span>
                  ) : (
                    <span
                      class={`fleet-classified-badge${row.classified ? ' fleet-classified-badge--yes' : ''}`}
                    >
                      {row.classified ? 'Yes' : 'No'}
                    </span>
                  )}
                </td>
                <td class="fleet-actions-cell">
                  {row.monitorHref ? (
                    <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
                      <a
                        class="fleet-action-link"
                        href={row.monitorHref}
                        target="_blank"
                        rel="noopener noreferrer"
                        title="Open honeypot admin monitor (login key required)"
                      >
                        Monitor
                      </a>
                      {row.isHoneypot && (
                        <a
                          class="fleet-action-link"
                          href="#threats"
                          title="Ver todas as ameaças interceptadas"
                          style={{ color: '#ffb347', borderColor: 'rgba(255, 179, 71, 0.4)' }}
                        >
                          Ameaças
                        </a>
                      )}
                    </div>
                  ) : row.isHoneypot ? (
                    <a
                      class="fleet-action-link"
                      href="#threats"
                      title="Ver todas as ameaças interceptadas"
                      style={{ color: '#ffb347', borderColor: 'rgba(255, 179, 71, 0.4)' }}
                    >
                      Ameaças
                    </a>
                  ) : (
                    <span class="fleet-metric-empty">—</span>
                  )}
                </td>
              </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {totalPages > 1 && (
        <div class="fleet-overview__pagination">
          <button
            type="button"
            class="fleet-overview__page-btn"
            disabled={safePage <= 1}
            onClick={() => setPage((p) => Math.max(1, p - 1))}
          >
            ← Prev
          </button>
          <span class="fleet-overview__page-info">
            Page {safePage} of {totalPages}
          </span>
          <button
            type="button"
            class="fleet-overview__page-btn"
            disabled={safePage >= totalPages}
            onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
          >
            Next →
          </button>
        </div>
      )}
    </section>
  );
}
