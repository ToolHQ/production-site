import { ThemeToggle } from './ThemeToggle';
import { useFleetCopilot } from '../context/FleetCopilotContext';
import { useDnorShell, type DnorView } from '../context/DnorShellContext';

export interface CopilotQuotaPill {
  remaining: number;
  max: number;
}

const NAV_ITEMS: { id: DnorView; label: string }[] = [
  { id: 'overview', label: 'Visão geral' },
  { id: 'nodes', label: 'Nós' },
  { id: 'incidents', label: 'Incidentes' },
  { id: 'reports', label: 'Relatórios' },
  { id: 'intel', label: 'Intel' },
  { id: 'settings', label: 'Config' },
];

interface DnorTopNavProps {
  liveAvailable?: boolean;
  liveConnecting?: boolean;
  copilotQuota?: CopilotQuotaPill | null;
}

export function DnorTopNav({
  liveAvailable = false,
  liveConnecting = false,
  copilotQuota = null,
}: DnorTopNavProps) {
  const { view, setView, period, setPeriod, setPaletteOpen } = useDnorShell();
  const { session: copilotSession } = useFleetCopilot();

  return (
    <header class="dnor-shell">
      <div class="dnor-shell__inner">
        <div class="dnor-shell__brand">
          <span class="dnor-shell__logo">DNOR</span>
        </div>

        <nav class="dnor-shell__nav" aria-label="Primary">
          {NAV_ITEMS.map((item) => (
            <button
              key={item.id}
              type="button"
              class={`dnor-shell__nav-item${view === item.id ? ' dnor-shell__nav-item--active' : ''}`}
              aria-current={view === item.id ? 'page' : undefined}
              onClick={() => setView(item.id)}
            >
              {item.label}
            </button>
          ))}
          {copilotSession.enabled && (
            <button
              type="button"
              class={`dnor-shell__nav-item dnor-shell__nav-item--copilot${view === 'fleet-copilot' ? ' dnor-shell__nav-item--active' : ''}${copilotSession.authenticated ? ' dnor-shell__nav-item--live' : ''}`}
              onClick={() => setView('fleet-copilot')}
              title="Fleet Copilot"
              aria-label="Fleet Copilot"
            >
              <span class="dnor-shell__nav-copilot-icon" aria-hidden="true">
                ✦
              </span>
              <span class="dnor-shell__nav-copilot-label">Copilot</span>
            </button>
          )}
        </nav>

        <div class="dnor-shell__actions">
          {view !== 'fleet-copilot' && (
          <button
            type="button"
            class="dnor-shell__search"
            onClick={() => setPaletteOpen(true)}
            aria-label="Search nodes, IPs, ASNs"
          >
            <span class="dnor-shell__search-icon">⌕</span>
            <span class="dnor-shell__search-placeholder">Buscar nós, IPs, ASNs…</span>
            <kbd class="dnor-shell__kbd">⌘K</kbd>
          </button>
          )}

          {view === 'fleet-copilot' && (
          <button
            type="button"
            class="dnor-shell__search dnor-shell__search--icon"
            onClick={() => setPaletteOpen(true)}
            aria-label="Search"
            title="Search (⌘K)"
          >
            <span class="dnor-shell__search-icon">⌕</span>
          </button>
          )}

          {view === 'nodes' && (
            <select
              class="dnor-shell__period"
              value={period}
              onChange={(e) => setPeriod(e.currentTarget.value as '24h' | '7d')}
              aria-label="Time range"
            >
              <option value="24h">Últimas 24h</option>
              <option value="7d">Últimos 7d</option>
            </select>
          )}

          {copilotQuota && view === 'fleet-copilot' && (
            <span
              class="dnor-shell__quota-pill"
              role="status"
              title="Consultas Fleet Copilot por minuto"
            >
              {copilotQuota.remaining}/{copilotQuota.max} req
            </span>
          )}

          <ThemeToggle compact />
          <span
            class={`dnor-shell__status${
              liveConnecting
                ? ' dnor-shell__status--connecting'
                : liveAvailable
                  ? ' dnor-shell__status--live'
                  : ''
            }`}
            title={
              liveConnecting
                ? 'Conectando aos dados live…'
                : liveAvailable
                  ? 'Dados live disponíveis'
                  : 'Dados live indisponíveis'
            }
            aria-live="polite"
            aria-label={
              liveConnecting ? 'Conectando' : liveAvailable ? 'Live' : 'Offline'
            }
          >
            <span class="dnor-shell__status-sr">
              {liveConnecting ? 'Conectando' : liveAvailable ? 'Live' : 'Offline'}
            </span>
          </span>
          <span class="dnor-shell__avatar" aria-hidden="true">D</span>
        </div>
      </div>
    </header>
  );
}
