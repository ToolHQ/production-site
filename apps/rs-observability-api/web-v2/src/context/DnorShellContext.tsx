import type { ComponentChildren } from 'preact';
import { createContext } from 'preact';
import { useContext, useEffect, useState, useCallback } from 'preact/hooks';

export type DnorView = 'overview' | 'nodes' | 'incidents' | 'reports' | 'intel' | 'settings' | 'fleet-copilot';
export type DnorPeriod = '24h' | '7d';

export interface DnorSearchHit {
  id: string;
  label: string;
  sublabel: string;
  query: string;
  view: DnorView;
}

interface DnorShellState {
  view: DnorView;
  setView: (view: DnorView) => void;
  period: DnorPeriod;
  setPeriod: (period: DnorPeriod) => void;
  nodeSearch: string;
  setNodeSearch: (query: string) => void;
  paletteOpen: boolean;
  setPaletteOpen: (open: boolean) => void;
}

const VALID_VIEWS = new Set<DnorView>([
  'overview',
  'nodes',
  'incidents',
  'reports',
  'intel',
  'settings',
  'fleet-copilot',
]);

function viewFromHash(): DnorView {
  const raw = window.location.hash.replace(/^#/, '').trim().toLowerCase();
  return VALID_VIEWS.has(raw as DnorView) ? (raw as DnorView) : 'overview';
}

const DnorShellContext = createContext<DnorShellState | null>(null);

export function DnorShellProvider({ children }: { children: ComponentChildren }) {
  const [view, setViewState] = useState<DnorView>(viewFromHash);
  const [period, setPeriod] = useState<DnorPeriod>('24h');
  const [nodeSearch, setNodeSearch] = useState('');
  const [paletteOpen, setPaletteOpen] = useState(false);

  const setView = useCallback((next: DnorView) => {
    setViewState(next);
    const hash = next === 'overview' ? '' : `#${next}`;
    if (window.location.hash !== hash) {
      window.history.replaceState(null, '', `${window.location.pathname}${window.location.search}${hash}`);
    }
  }, []);

  useEffect(() => {
    const onHash = () => setViewState(viewFromHash());
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        setPaletteOpen((open) => !open);
      }
      if (event.key === 'Escape') {
        setPaletteOpen(false);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  return (
    <DnorShellContext.Provider
      value={{
        view,
        setView,
        period,
        setPeriod,
        nodeSearch,
        setNodeSearch,
        paletteOpen,
        setPaletteOpen,
      }}
    >
      {children}
    </DnorShellContext.Provider>
  );
}

export function useDnorShell(): DnorShellState {
  const ctx = useContext(DnorShellContext);
  if (!ctx) throw new Error('useDnorShell must be used within DnorShellProvider');
  return ctx;
}
