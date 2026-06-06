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
  timeElapsed: number | null;
  userAgent: string | null;
}

export interface HoneypotRequestsResponse {
  total: number;
  rows: HoneypotRequest[];
}

export interface HoneypotFilters {
  method?: string;
  path?: string;
  ip?: string;
  classification?: string;
  exclude_internal?: boolean;
}

export interface UseHoneypotRequestsResult {
  data: HoneypotRequestsResponse | null;
  error: string | null;
  loading: boolean;
  refresh: () => void;
}

export function useHoneypotRequests(limit: number, offset: number, filters?: HoneypotFilters): UseHoneypotRequestsResult {
  const [data, setData] = useState<HoneypotRequestsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [tick, setTick] = useState(0);

  // We need to stringify filters for the dependency array
  const filtersKey = JSON.stringify(filters || {});

  useEffect(() => {
    let mounted = true;
    
    async function fetchRequests() {
      setLoading(true);
      try {
        const params = new URLSearchParams({
          limit: limit.toString(),
          offset: offset.toString()
        });
        if (filters?.method) params.append('method', filters.method);
        if (filters?.path) params.append('path', filters.path);
        if (filters?.ip) params.append('ip', filters.ip);
        if (filters?.classification) params.append('classification', filters.classification);
        if (filters?.exclude_internal) params.append('exclude_internal', 'true');

        const response = await fetch(`/api/live/honeypot-requests?${params.toString()}`, { cache: 'no-store' });
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
  }, [limit, offset, filtersKey, tick]);

  return { data, error, loading, refresh: () => setTick(t => t + 1) };
}
