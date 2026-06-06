import { useState, useEffect } from 'preact/hooks';

export interface HoneypotRequest {
  id: number;
  timestamp: string;
  method: string;
  path: string;
  statusCode: number;
  remoteHostname: string | null;
  remoteIp: string | null;
  country: string | null;
  classification: string | null;
}

export interface HoneypotRequestsResponse {
  total: number;
  rows: HoneypotRequest[];
}

export interface UseHoneypotRequestsResult {
  data: HoneypotRequestsResponse | null;
  error: string | null;
  loading: boolean;
  refresh: () => void;
}

export function useHoneypotRequests(limit: number, offset: number): UseHoneypotRequestsResult {
  const [data, setData] = useState<HoneypotRequestsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [tick, setTick] = useState(0);

  useEffect(() => {
    let mounted = true;
    
    async function fetchRequests() {
      setLoading(true);
      try {
        const response = await fetch(`/api/live/honeypot-requests?limit=${limit}&offset=${offset}`, { cache: 'no-store' });
        if (!response.ok) throw new Error(`API returned HTTP ${response.status}`);
        const json: HoneypotRequestsResponse = await response.json();
        if (mounted) {
          setData(json);
          setError(null);
        }
      } catch (err: unknown) {
        if (mounted) {
          setError((err as Error).message || 'Falha ao buscar histórico do Honeypot.');
        }
      } finally {
        if (mounted) {
          setLoading(false);
        }
      }
    }

    fetchRequests();
    return () => { mounted = false; };
  }, [limit, offset, tick]);

  return { data, error, loading, refresh: () => setTick(t => t + 1) };
}
