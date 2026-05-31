import type { ComponentChildren } from 'preact';
import { createContext } from 'preact';
import { useCallback, useContext, useEffect, useState } from 'preact/hooks';
import type { CopilotSession } from '../types/fleetCopilot';

interface FleetCopilotState {
  session: CopilotSession;
  loading: boolean;
  refresh: () => Promise<void>;
  logout: () => Promise<void>;
}

const FleetCopilotContext = createContext<FleetCopilotState | null>(null);

async function fetchSession(): Promise<CopilotSession> {
  const res = await fetch('/api/fleet/copilot/session', { credentials: 'same-origin' });
  if (res.status === 404) {
    return { enabled: false, authenticated: false };
  }
  if (!res.ok) {
    return { enabled: true, authenticated: false };
  }
  return (await res.json()) as CopilotSession;
}

export function FleetCopilotProvider({ children }: { children: ComponentChildren }) {
  const [session, setSession] = useState<CopilotSession>({
    enabled: true,
    authenticated: false,
  });
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    try {
      setSession(await fetchSession());
    } catch {
      setSession({ enabled: false, authenticated: false });
    } finally {
      setLoading(false);
    }
  }, []);

  const logout = useCallback(async () => {
    await fetch('/api/fleet/copilot/logout', {
      method: 'POST',
      credentials: 'same-origin',
    });
    await refresh();
  }, [refresh]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  return (
    <FleetCopilotContext.Provider value={{ session, loading, refresh, logout }}>
      {children}
    </FleetCopilotContext.Provider>
  );
}

export function useFleetCopilot(): FleetCopilotState {
  const ctx = useContext(FleetCopilotContext);
  if (!ctx) throw new Error('useFleetCopilot must be used within FleetCopilotProvider');
  return ctx;
}
