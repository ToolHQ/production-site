import { useState, useEffect } from 'preact/hooks';

export interface AlertThresholds {
  disk_warn: number;   // % — pre-warn before DiskPressure (default 80)
  disk_crit: number;   // % — critical (default 90)
  mem_warn: number;    // % — pre-warn before MemPressure (default 85)
  mem_crit: number;    // % — critical (default 92)
  cpu_warn: number;    // % — sustained CPU warn (default 70)
  cpu_crit: number;    // % — critical (default 90)
}

export const DEFAULT_THRESHOLDS: AlertThresholds = {
  disk_warn: 80,
  disk_crit: 90,
  mem_warn: 85,
  mem_crit: 92,
  cpu_warn: 70,
  cpu_crit: 90,
};

export function useAlertThresholds() {
  const [thresholds, setThresholds] = useState<AlertThresholds>(() => {
    try {
      const saved = localStorage.getItem('alert-thresholds');
      return saved ? { ...DEFAULT_THRESHOLDS, ...JSON.parse(saved) } : DEFAULT_THRESHOLDS;
    } catch {
      return DEFAULT_THRESHOLDS;
    }
  });

  useEffect(() => {
    localStorage.setItem('alert-thresholds', JSON.stringify(thresholds));
  }, [thresholds]);

  const update = (patch: Partial<AlertThresholds>) => {
    setThresholds((prev) => ({ ...prev, ...patch }));
  };

  const reset = () => {
    setThresholds(DEFAULT_THRESHOLDS);
    localStorage.removeItem('alert-thresholds');
  };

  return { thresholds, update, reset };
}
