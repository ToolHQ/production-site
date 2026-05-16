import { useState, useEffect, useRef } from 'preact/hooks';
import type { LiveOverview } from '../types/api';

export interface UseLiveOverviewResult {
  data: LiveOverview | null;
  error: string | null;
  lastFetchAt: number | null;
}

const POLL_INTERVAL_MS = 15_000;

export function useLiveOverview(): UseLiveOverviewResult {
  const [data, setData] = useState<LiveOverview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lastFetchAt, setLastFetchAt] = useState<number | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  async function fetchLive() {
    try {
      const response = await fetch('/api/live/overview', { cache: 'no-store' });
      if (!response.ok) throw new Error(`Live API: HTTP ${response.status}`);
      const json: LiveOverview = await response.json();
      setData(json);
      setLastFetchAt(Date.now());
      // Propagar erros soft (stale / degraded) mas não derrubar o estado
      const errors: string[] = [];
      if (json.error) errors.push(json.stale ? `Cached live: ${json.error}` : json.error);
      if (json.metrics?.error) errors.push(json.metrics.stale ? `Cached metrics: ${json.metrics.error}` : json.metrics.error);
      setError(errors.length ? errors.join(' | ') : null);
    } catch (err: unknown) {
      setError((err as Error).message || 'Failed to refresh live data.');
    }
  }

  useEffect(() => {
    fetchLive();
    timerRef.current = setInterval(() => {
      fetchLive();
    }, POLL_INTERVAL_MS);
    return () => {
      if (timerRef.current !== null) clearInterval(timerRef.current);
    };
  }, []);

  return { data, error, lastFetchAt };
}
