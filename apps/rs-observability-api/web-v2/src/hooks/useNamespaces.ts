import { useState, useEffect, useRef } from 'preact/hooks';
import type { NamespacesData } from '../types/api';

export interface UseNamespacesResult {
  data: NamespacesData | null;
  error: string | null;
  lastFetchAt: number | null;
}

const POLL_INTERVAL_MS = 60_000;

export function useNamespaces(): UseNamespacesResult {
  const [data, setData] = useState<NamespacesData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lastFetchAt, setLastFetchAt] = useState<number | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  async function fetchNamespaces() {
    try {
      const response = await fetch('/api/namespaces', { cache: 'no-store' });
      if (!response.ok) throw new Error(`Namespaces API: HTTP ${response.status}`);
      const json: NamespacesData = await response.json();
      setData(json);
      setLastFetchAt(Date.now());
      setError(json.error ?? null);
    } catch (err: unknown) {
      setError((err as Error).message || 'Falha ao buscar quotas de namespaces.');
    }
  }

  useEffect(() => {
    fetchNamespaces();
    timerRef.current = setInterval(fetchNamespaces, POLL_INTERVAL_MS);
    return () => {
      if (timerRef.current !== null) clearInterval(timerRef.current);
    };
  }, []);

  return { data, error, lastFetchAt };
}
