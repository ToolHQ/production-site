// Utilitários de formatação puros — sem dependência de DOM

export function escapeHtml(value: unknown): string {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

export function formatTimestamp(raw: string | null | undefined): string {
  if (!raw) return 'Timestamp unavailable';
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? raw : date.toLocaleString();
}

export function formatEpoch(epochSeconds: number | null | undefined): string {
  if (!epochSeconds) return 'Waiting for refresh...';
  return new Date(epochSeconds * 1000).toLocaleTimeString();
}

export function formatShortClock(epochSeconds: number | null | undefined): string {
  if (!epochSeconds) return 'Waiting';
  return new Date(epochSeconds * 1000).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

export function formatRelativeTime(raw: string | null | undefined): string {
  if (!raw) return 'timestamp unavailable';
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) return raw;
  const diffMs = Date.now() - date.getTime();
  const minutes = Math.round(diffMs / 60000);
  const hours = Math.round(diffMs / 3600000);
  const days = Math.round(diffMs / 86400000);
  if (minutes < 1) return 'generated just now';
  if (minutes < 60) return `generated ${minutes} minute${minutes === 1 ? '' : 's'} ago`;
  if (hours < 48) return `generated ${hours} hour${hours === 1 ? '' : 's'} ago`;
  return `generated ${days} day${days === 1 ? '' : 's'} ago`;
}

export function formatCompactRelativeTime(raw: string | null | undefined): string {
  if (!raw) return 'time unknown';
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) return raw;
  const diffMs = Math.max(0, Date.now() - date.getTime());
  const minutes = Math.round(diffMs / 60000);
  const hours = Math.round(diffMs / 3600000);
  const days = Math.round(diffMs / 86400000);
  if (minutes < 1) return 'now';
  if (minutes < 60) return `${minutes}m ago`;
  if (hours < 48) return `${hours}h ago`;
  return `${days}d ago`;
}

export function formatMetaDate(raw: string | null | undefined): string {
  if (!raw) return 'date unavailable';
  const date = new Date(raw);
  return Number.isNaN(date.getTime())
    ? raw
    : date.toLocaleString([], { month: 'numeric', day: 'numeric', hour: 'numeric', minute: '2-digit' });
}

export function formatBytes(bytes: number | null | undefined): string {
  if (!Number.isFinite(bytes as number) || (bytes as number) <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value = bytes as number;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(value >= 10 || unit === 0 ? 0 : 1)} ${units[unit]}`;
}

export function formatPercent(value: number | null | undefined): string {
  return `${Number(value || 0).toFixed(1)}%`;
}

export function formatCores(value: number | null | undefined): string {
  return `${Number(value || 0).toFixed(2)} cores`;
}

export function formatDiscreteCount(value: number | null | undefined): string {
  return Math.round(Number(value || 0)).toLocaleString();
}

export function statusClass(status: string): string {
  if (status === 'down') return 'down';
  if (status === 'degraded') return 'degraded';
  if (status === 'healthy') return 'healthy';
  return 'telemetry';
}

export function tableStatusClass(readiness: string): string {
  if (readiness === 'deployable') return 'deployable';
  if (readiness === 'partial') return 'partial';
  return 'wip';
}

export function isCompactViewport(): boolean {
  return window.matchMedia('(max-width: 560px)').matches;
}

export function isCondensedViewport(): boolean {
  return window.matchMedia('(max-width: 980px)').matches;
}
