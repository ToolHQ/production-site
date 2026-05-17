import { useEffect, useState } from 'preact/hooks';

/**
 * Returns seconds remaining until the next refresh cycle.
 * `intervalMs` should match the hook's polling interval.
 * `lastRefreshEpoch` resets the countdown when a fresh response arrives.
 */
export function useRefreshCountdown(intervalMs: number, lastRefreshEpoch: number | null): number {
  const intervalSec = Math.round(intervalMs / 1000);
  const [remaining, setRemaining] = useState(intervalSec);

  // Reset countdown whenever a new response arrives
  useEffect(() => {
    setRemaining(intervalSec);
  }, [lastRefreshEpoch, intervalSec]);

  // Tick every second
  useEffect(() => {
    const id = setInterval(() => {
      setRemaining((r) => (r <= 1 ? intervalSec : r - 1));
    }, 1_000);
    return () => clearInterval(id);
  }, [intervalSec]);

  return remaining;
}
