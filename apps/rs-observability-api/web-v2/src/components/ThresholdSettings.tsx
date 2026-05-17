
import type { AlertThresholds } from '../hooks/useAlertThresholds';
import { DEFAULT_THRESHOLDS } from '../hooks/useAlertThresholds';
import styles from './ThresholdSettings.module.css';

interface ThresholdSettingsProps {
  thresholds: AlertThresholds;
  onUpdate: (patch: Partial<AlertThresholds>) => void;
  onReset: () => void;
  onClose: () => void;
}

interface SliderProps {
  label: string;
  value: number;
  defaultValue: number;
  min?: number;
  max?: number;
  color?: string;
  onChange: (v: number) => void;
}

function ThresholdSlider({ label, value, defaultValue, min = 50, max = 99, color = '#0d7c72', onChange }: SliderProps) {
  const pct = ((value - min) / (max - min)) * 100;
  const defaultPct = ((defaultValue - min) / (max - min)) * 100;

  return (
    <div class={styles.sliderRow}>
      <div class={styles.sliderLabel}>
        <span>{label}</span>
        <span class={styles.sliderValue} style={{ color }}>{value}%</span>
      </div>
      <div class={styles.sliderTrackWrapper}>
        <input
          type="range"
          min={min}
          max={max}
          value={value}
          onInput={(e) => onChange(Number(e.currentTarget.value))}
          class={styles.sliderInput}
          style={{ '--pct': `${pct}%`, '--color': color } as any}
        />
        <div class={styles.defaultMark} style={{ left: `${defaultPct}%` }} title={`Default: ${defaultValue}%`} />
      </div>
    </div>
  );
}

export function ThresholdSettings({ thresholds, onUpdate, onReset, onClose }: ThresholdSettingsProps) {
  return (
    <div class={styles.backdrop} onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div class={styles.modal} role="dialog" aria-modal="true" aria-label="Alert Threshold Settings">
        <div class={styles.header}>
          <h2>Alert Thresholds</h2>
          <button class={styles.closeBtn} onClick={onClose} aria-label="Close settings">✕</button>
        </div>

        <p class={styles.hint}>
          Pre-warn alerts fire before Kubernetes formally marks a node as under pressure.
          The triangle marker (▾) shows the default value.
        </p>

        <div class={styles.group}>
          <div class={styles.groupTitle}>💾 Disk</div>
          <ThresholdSlider
            label="Warning"
            value={thresholds.disk_warn}
            defaultValue={DEFAULT_THRESHOLDS.disk_warn}
            color="#f59e0b"
            onChange={(v) => onUpdate({ disk_warn: v })}
          />
          <ThresholdSlider
            label="Critical"
            value={thresholds.disk_crit}
            defaultValue={DEFAULT_THRESHOLDS.disk_crit}
            color="#ef4444"
            onChange={(v) => onUpdate({ disk_crit: v })}
          />
        </div>

        <div class={styles.group}>
          <div class={styles.groupTitle}>🧠 Memory</div>
          <ThresholdSlider
            label="Warning"
            value={thresholds.mem_warn}
            defaultValue={DEFAULT_THRESHOLDS.mem_warn}
            color="#f59e0b"
            onChange={(v) => onUpdate({ mem_warn: v })}
          />
          <ThresholdSlider
            label="Critical"
            value={thresholds.mem_crit}
            defaultValue={DEFAULT_THRESHOLDS.mem_crit}
            color="#ef4444"
            onChange={(v) => onUpdate({ mem_crit: v })}
          />
        </div>

        <div class={styles.group}>
          <div class={styles.groupTitle}>⚡ CPU</div>
          <ThresholdSlider
            label="Warning"
            value={thresholds.cpu_warn}
            defaultValue={DEFAULT_THRESHOLDS.cpu_warn}
            color="#f59e0b"
            onChange={(v) => onUpdate({ cpu_warn: v })}
          />
          <ThresholdSlider
            label="Critical"
            value={thresholds.cpu_crit}
            defaultValue={DEFAULT_THRESHOLDS.cpu_crit}
            color="#ef4444"
            onChange={(v) => onUpdate({ cpu_crit: v })}
          />
        </div>

        <div class={styles.footer}>
          <button class={styles.resetBtn} onClick={onReset}>↺ Reset to Defaults</button>
          <button class={styles.applyBtn} onClick={onClose}>✓ Apply</button>
        </div>
      </div>
    </div>
  );
}
