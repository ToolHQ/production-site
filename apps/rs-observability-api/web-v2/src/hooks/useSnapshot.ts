import { useState, useEffect, useRef } from 'preact/hooks';
import type { SnapshotSummary, CatalogData, ReportsData } from '../types/api';

export interface UseSnapshotResult {
  summary: SnapshotSummary | null;
  catalog: CatalogData | null;
  reports: ReportsData | null;
  error: string | null;
}

const POLL_INTERVAL_MS = 300_000; // 5 min

export function useSnapshot(): UseSnapshotResult {
  const [summary, setSummary] = useState<SnapshotSummary | null>(null);
  const [catalog, setCatalog] = useState<CatalogData | null>(null);
  const [reports, setReports] = useState<ReportsData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  async function fetchSnapshot() {
    try {
      const [summaryRes, catalogRes, reportsRes] = await Promise.all([
        fetch('/api/catalog/summary', { cache: 'no-store' }),
        fetch('/api/catalog', { cache: 'no-store' }),
        fetch('/api/reports', { cache: 'no-store' }),
      ]);
      if (!summaryRes.ok || !catalogRes.ok || !reportsRes.ok) {
        throw new Error('Snapshot API returned an unexpected status.');
      }
      const [summaryData, catalogData, reportsData] = await Promise.all([
        summaryRes.json() as Promise<SnapshotSummary>,
        catalogRes.json() as Promise<CatalogData>,
        reportsRes.json() as Promise<ReportsData>,
      ]);
      setSummary(summaryData);
      setCatalog(catalogData);
      setReports(reportsData);
      setError(null);
    } catch (err: unknown) {
      setError((err as Error).message || 'Failed to refresh snapshot data.');
    }
  }

  useEffect(() => {
    fetchSnapshot();
    timerRef.current = setInterval(fetchSnapshot, POLL_INTERVAL_MS);
    return () => {
      if (timerRef.current !== null) clearInterval(timerRef.current);
    };
  }, []);

  return { summary, catalog, reports, error };
}
