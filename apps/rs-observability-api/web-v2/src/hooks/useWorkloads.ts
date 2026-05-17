import { useState, useEffect, useRef } from 'preact/hooks';
import type { WorkloadsData } from '../types/api';

export interface UseWorkloadsResult {
  data: WorkloadsData | null;
  error: string | null;
  lastFetchAt: number | null;
}

const POLL_INTERVAL_MS = 60_000;

export function useWorkloads(): UseWorkloadsResult {
  const [data, setData] = useState<WorkloadsData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lastFetchAt, setLastFetchAt] = useState<number | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  async function fetchWorkloads() {
    try {
      const response = await fetch('/api/workloads', { cache: 'no-store' });
      if (!response.ok) throw new Error(`Workloads API: HTTP ${response.status}`);
      const json: WorkloadsData = await response.json();
      setData(json);
      setLastFetchAt(Date.now());
      setError(json.error ?? null);
    } catch (err: unknown) {
      setError((err as Error).message || 'Falha ao buscar workloads.');
    }
  }

  useEffect(() => {
    fetchWorkloads();
    timerRef.current = setInterval(fetchWorkloads, POLL_INTERVAL_MS);
    return () => {
      if (timerRef.current !== null) clearInterval(timerRef.current);
    };
  }, []);

  return { data, error, lastFetchAt };
}
