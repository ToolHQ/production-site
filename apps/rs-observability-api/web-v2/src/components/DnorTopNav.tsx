import { ThemeToggle } from './ThemeToggle';
import { useFleetCopilot } from '../context/FleetCopilotContext';
import { useDnorShell, type DnorView } from '../context/DnorShellContext';

const NAV_ITEMS: { id: DnorView; label: string }[] = [
  { id: 'overview', label: 'Overview' },
  { id: 'nodes', label: 'Nodes' },
  { id: 'incidents', label: 'Incidents' },
  { id: 'reports', label: 'Reports' },
  { id: 'intel', label: 'Intel' },
  { id: 'settings', label: 'Settings' },
];

interface DnorTopNavProps {
  liveAvailable?: boolean;
}

export function DnorTopNav({ liveAvailable = false }: DnorTopNavProps) {
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
            >
              Copilot
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
            <span class="dnor-shell__search-placeholder">Search nodes, IPs, ASNs…</span>
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
              <option value="24h">Last 24h</option>
              <option value="7d">Last 7d</option>
            </select>
          )}

          <ThemeToggle />
          <span
            class={`dnor-shell__status${liveAvailable ? ' dnor-shell__status--live' : ''}`}
            title={liveAvailable ? 'Cluster live data available' : 'Live data unavailable'}
            aria-label={liveAvailable ? 'Live' : 'Offline'}
          />
          <span class="dnor-shell__avatar" aria-hidden="true">D</span>
        </div>
      </div>
    </header>
  );
}
