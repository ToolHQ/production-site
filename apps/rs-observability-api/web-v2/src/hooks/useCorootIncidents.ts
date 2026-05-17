import { useState, useEffect, useRef } from 'preact/hooks';
import type { CorootIncidentsData } from '../types/api';

export interface UseCorootIncidentsResult {
  data: CorootIncidentsData | null;
  error: string | null;
  lastFetchAt: number | null;
}

const POLL_INTERVAL_MS = 60_000;

export function useCorootIncidents(): UseCorootIncidentsResult {
  const [data, setData] = useState<CorootIncidentsData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lastFetchAt, setLastFetchAt] = useState<number | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  async function fetchIncidents() {
    try {
      const response = await fetch('/api/coroot-incidents', { cache: 'no-store' });
      if (!response.ok) throw new Error(`Coroot Incidents API: HTTP ${response.status}`);
      const json: CorootIncidentsData = await response.json();
      setData(json);
      setLastFetchAt(Date.now());
      setError(json.error ?? null);
    } catch (err: unknown) {
      setError((err as Error).message || 'Falha ao buscar incidentes do Coroot.');
    }
  }

  useEffect(() => {
    fetchIncidents();
    timerRef.current = setInterval(fetchIncidents, POLL_INTERVAL_MS);
    return () => {
      if (timerRef.current !== null) clearInterval(timerRef.current);
    };
  }, []);

  return { data, error, lastFetchAt };
}
