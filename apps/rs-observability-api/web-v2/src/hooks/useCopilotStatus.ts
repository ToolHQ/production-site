import { useEffect, useState } from 'preact/hooks';
import type { CopilotStatus } from '../types/fleetCopilot';

export function useCopilotStatus(active: boolean, refreshKey = 0): CopilotStatus | null {
  const [status, setStatus] = useState<CopilotStatus | null>(null);

  useEffect(() => {
    if (!active) {
      setStatus(null);
      return;
    }
    let cancelled = false;
    void fetch('/api/fleet/copilot/status', { credentials: 'same-origin' })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (!cancelled) setStatus(data as CopilotStatus | null);
      })
      .catch(() => {
        if (!cancelled) setStatus(null);
      });
    return () => {
      cancelled = true;
    };
  }, [active, refreshKey]);

  return status;
}
