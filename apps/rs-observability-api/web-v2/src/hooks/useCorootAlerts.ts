import { useState, useEffect, useRef } from 'preact/hooks';
import type { CorootAlertsData } from '../types/api';

export interface UseCorootAlertsResult {
  data: CorootAlertsData | null;
  error: string | null;
  lastFetchAt: number | null;
}

const POLL_INTERVAL_MS = 30_000;

export function useCorootAlerts(): UseCorootAlertsResult {
  const [data, setData] = useState<CorootAlertsData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lastFetchAt, setLastFetchAt] = useState<number | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  async function fetchAlerts() {
    try {
      const response = await fetch('/api/coroot-alerts', { cache: 'no-store' });
      if (!response.ok) throw new Error(`Coroot Alerts API: HTTP ${response.status}`);
      const json: CorootAlertsData = await response.json();
      setData(json);
      setLastFetchAt(Date.now());
      setError(json.error ?? null);
    } catch (err: unknown) {
      setError((err as Error).message || 'Falha ao buscar alertas do Coroot.');
    }
  }

  useEffect(() => {
    fetchAlerts();
    timerRef.current = setInterval(fetchAlerts, POLL_INTERVAL_MS);
    return () => {
      if (timerRef.current !== null) clearInterval(timerRef.current);
    };
  }, []);

  return { data, error, lastFetchAt };
}
