import { useState, useEffect, useRef } from 'preact/hooks';
import type { CertificatesData } from '../types/api';

export interface UseCertificatesResult {
  data: CertificatesData | null;
  error: string | null;
  lastFetchAt: number | null;
}

const POLL_INTERVAL_MS = 60_000;

export function useCertificates(): UseCertificatesResult {
  const [data, setData] = useState<CertificatesData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lastFetchAt, setLastFetchAt] = useState<number | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  async function fetchCertificates() {
    try {
      const response = await fetch('/api/certificates', { cache: 'no-store' });
      if (!response.ok) throw new Error(`Certificates API: HTTP ${response.status}`);
      const json: CertificatesData = await response.json();
      setData(json);
      setLastFetchAt(Date.now());
      setError(json.error ?? null);
    } catch (err: unknown) {
      setError((err as Error).message || 'Falha ao buscar certificados.');
    }
  }

  useEffect(() => {
    fetchCertificates();
    timerRef.current = setInterval(fetchCertificates, POLL_INTERVAL_MS);
    return () => {
      if (timerRef.current !== null) clearInterval(timerRef.current);
    };
  }, []);

  return { data, error, lastFetchAt };
}
