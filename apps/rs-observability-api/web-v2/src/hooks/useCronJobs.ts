import { useState, useEffect, useRef } from 'preact/hooks';
import type { CronJobsData } from '../types/api';

export interface UseCronJobsResult {
  data: CronJobsData | null;
  error: string | null;
  lastFetchAt: number | null;
}

const POLL_INTERVAL_MS = 60_000;

export function useCronJobs(): UseCronJobsResult {
  const [data, setData] = useState<CronJobsData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lastFetchAt, setLastFetchAt] = useState<number | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  async function fetchCronJobs() {
    try {
      const response = await fetch('/api/cronjobs', { cache: 'no-store' });
      if (!response.ok) throw new Error(`CronJobs API: HTTP ${response.status}`);
      const json: CronJobsData = await response.json();
      setData(json);
      setLastFetchAt(Date.now());
      setError(json.error ?? null);
    } catch (err: unknown) {
      setError((err as Error).message || 'Falha ao buscar CronJobs.');
    }
  }

  useEffect(() => {
    fetchCronJobs();
    timerRef.current = setInterval(fetchCronJobs, POLL_INTERVAL_MS);
    return () => {
      if (timerRef.current !== null) clearInterval(timerRef.current);
    };
  }, []);

  return { data, error, lastFetchAt };
}
