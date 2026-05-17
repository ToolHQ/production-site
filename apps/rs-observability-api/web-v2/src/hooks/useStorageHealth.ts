import { useState, useEffect, useRef } from 'preact/hooks';
import type { LonghornData } from '../types/api';

export interface UseStorageHealthResult {
  data: LonghornData | null;
  error: string | null;
  lastFetchAt: number | null;
}

const POLL_INTERVAL_MS = 60_000;

export function useStorageHealth(): UseStorageHealthResult {
  const [data, setData] = useState<LonghornData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lastFetchAt, setLastFetchAt] = useState<number | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  async function fetchVolumes() {
    try {
      const response = await fetch('/api/longhorn', { cache: 'no-store' });
      if (!response.ok) throw new Error(`Longhorn API: HTTP ${response.status}`);
      const json: LonghornData = await response.json();
      setData(json);
      setLastFetchAt(Date.now());
      setError(json.error ?? null);
    } catch (err: unknown) {
      setError((err as Error).message || 'Falha ao buscar volumes Longhorn.');
    }
  }

  useEffect(() => {
    fetchVolumes();
    timerRef.current = setInterval(fetchVolumes, POLL_INTERVAL_MS);
    return () => {
      if (timerRef.current !== null) clearInterval(timerRef.current);
    };
  }, []);

  return { data, error, lastFetchAt };
}
