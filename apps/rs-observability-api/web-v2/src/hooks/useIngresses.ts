import { useState, useEffect, useRef } from 'preact/hooks';
import type { IngressesData } from '../types/api';

export interface UseIngressesResult {
  data: IngressesData | null;
  error: string | null;
  lastFetchAt: number | null;
}

const POLL_INTERVAL_MS = 60_000;

export function useIngresses(): UseIngressesResult {
  const [data, setData] = useState<IngressesData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lastFetchAt, setLastFetchAt] = useState<number | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  async function fetchIngresses() {
    try {
      const response = await fetch('/api/ingresses', { cache: 'no-store' });
      if (!response.ok) throw new Error(`Ingresses API: HTTP ${response.status}`);
      const json: IngressesData = await response.json();
      setData(json);
      setLastFetchAt(Date.now());
      setError(json.error ?? null);
    } catch (err: unknown) {
      setError((err as Error).message || 'Falha ao buscar Ingresses.');
    }
  }

  useEffect(() => {
    fetchIngresses();
    timerRef.current = setInterval(fetchIngresses, POLL_INTERVAL_MS);
    return () => {
      if (timerRef.current !== null) clearInterval(timerRef.current);
    };
  }, []);

  return { data, error, lastFetchAt };
}
