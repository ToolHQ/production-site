import { useState, useRef, useEffect } from 'preact/hooks';
import type { LiveOverview, MetricsData } from '../types/api';
import { exportJSON, exportCSVBundle } from '../utils/export';
import { useDnorShell } from '../context/DnorShellContext';
import styles from './ExportMenu.module.css';

interface ExportMenuProps {
  live: LiveOverview | null;
  metrics: MetricsData | null;
}

export function ExportMenu({ live, metrics }: ExportMenuProps) {
  const [open, setOpen] = useState(false);
  const [flash, setFlash] = useState<string | null>(null);
  const ref = useRef<HTMLDivElement>(null);
  const { period } = useDnorShell();

  // Close on outside click
  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  const doExport = (format: 'json' | 'csv') => {
    setOpen(false);
    if (format === 'json') exportJSON(live, metrics, period);
    else exportCSVBundle(live, metrics, period);
    setFlash(format.toUpperCase());
    setTimeout(() => setFlash(null), 1800);
  };

  const hasData = live?.available || metrics?.available;

  return (
    <div class={styles.wrapper} ref={ref}>
      <button
        class={`${styles.trigger} ${flash ? styles.triggerFlash : ''}`}
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="true"
        aria-expanded={open}
        title="Export cluster snapshot"
        disabled={!hasData}
      >
        {flash ? `✓ ${flash}` : '⬇ Export'}
      </button>

      {open && (
        <div class={styles.menu} role="menu">
          <button
            class={styles.item}
            role="menuitem"
            onClick={() => doExport('json')}
          >
            <span class={styles.itemIcon}>{ }</span>
            <span class={styles.itemLabel}>JSON</span>
            <span class={styles.itemMeta}>Full snapshot with series</span>
          </button>
          <button
            class={styles.item}
            role="menuitem"
            onClick={() => doExport('csv')}
          >
            <span class={styles.itemIcon}>⊞</span>
            <span class={styles.itemLabel}>CSV</span>
            <span class={styles.itemMeta}>Fleet · Nodes · Incidents · Services</span>
          </button>
        </div>
      )}
    </div>
  );
}
