import { useEffect, useMemo, useState } from 'preact/hooks';
import type { LiveOverview } from '../types/api';
import { useDnorShell, type DnorSearchHit } from '../context/DnorShellContext';

interface GlobalSearchPaletteProps {
  live: LiveOverview | null;
}

function buildSearchIndex(live: LiveOverview | null): DnorSearchHit[] {
  if (!live?.nodes) return [];
  const hits: DnorSearchHit[] = [];

  for (const node of live.nodes) {
    hits.push({
      id: `node:${node.name}`,
      label: node.name,
      sublabel: `${node.cluster} · ${node.ip}`,
      query: node.name,
      view: 'nodes',
    });
    hits.push({
      id: `ip:${node.ip}`,
      label: node.ip,
      sublabel: `${node.cluster} · ${node.name}`,
      query: node.ip,
      view: 'nodes',
    });
  }

  for (const hp of live.honeypot?.nodes ?? []) {
    hits.push({
      id: `hp:${hp.id}`,
      label: `Honeypot · ${hp.cluster}`,
      sublabel: hp.instance_host,
      query: hp.instance_host,
      view: 'nodes',
    });
  }

  return hits;
}

export function GlobalSearchPalette({ live }: GlobalSearchPaletteProps) {
  const { paletteOpen, setPaletteOpen, setView, setNodeSearch } = useDnorShell();
  const [query, setQuery] = useState('');
  const index = useMemo(() => buildSearchIndex(live), [live]);

  const results = useMemo(() => {
    if (!query.trim()) return index.slice(0, 8);
    const q = query.toLowerCase();
    return index
      .filter(
        (hit) =>
          hit.label.toLowerCase().includes(q) ||
          hit.sublabel.toLowerCase().includes(q) ||
          hit.query.toLowerCase().includes(q),
      )
      .slice(0, 12);
  }, [index, query]);

  useEffect(() => {
    if (!paletteOpen) setQuery('');
  }, [paletteOpen]);

  if (!paletteOpen) return null;

  const pick = (hit: DnorSearchHit) => {
    setView(hit.view);
    setNodeSearch(hit.query);
    setPaletteOpen(false);
  };

  return (
    <div
      class="dnor-palette-backdrop"
      onClick={() => setPaletteOpen(false)}
      role="presentation"
    >
      <div
        class="dnor-palette"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-label="Global search"
      >
        <input
          class="dnor-palette__input"
          type="search"
          placeholder="Search nodes, IPs, ASNs…"
          value={query}
          onInput={(e) => setQuery(e.currentTarget.value)}
          autoFocus
        />
        <ul class="dnor-palette__results">
          {results.length === 0 ? (
            <li class="dnor-palette__empty">No matches</li>
          ) : (
            results.map((hit) => (
              <li key={hit.id}>
                <button type="button" class="dnor-palette__hit" onClick={() => pick(hit)}>
                  <span class="dnor-palette__hit-label">{hit.label}</span>
                  <span class="dnor-palette__hit-sub">{hit.sublabel}</span>
                </button>
              </li>
            ))
          )}
        </ul>
      </div>
    </div>
  );
}
