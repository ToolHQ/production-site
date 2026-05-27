import { allDefault } from '../sqlite3.js'
import { version } from '../constants.js'

const CACHE_MS = 15_000

let cache = {
  expiresAt: 0,
  body: '',
}

function escapeLabelValue(value) {
  return String(value).replace(/\\/g, '\\\\').replace(/\n/g, '\\n').replace(/"/g, '\\"')
}

/**
 * @returns {Promise<{ total: number, last24h: number, classified: number, unclassified: number }>}
 */
async function loadThreatCounts() {
  const [[{ total }], [{ last24h }], [{ classified }]] = await Promise.all([
    allDefault('SELECT COUNT(*) AS total FROM httpRequests'),
    allDefault(`
SELECT COUNT(*) AS last24h FROM httpRequests
WHERE timestamp >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-1 day')`),
    allDefault(`
SELECT COUNT(*) AS classified FROM httpRequests
WHERE classification IS NOT NULL AND classification != '' AND classification != 'unclassified'`),
  ])

  return {
    total,
    last24h,
    classified,
    unclassified: total - classified,
  }
}

/**
 * Prometheus text exposition 0.0.4 for qdbback honeypot counters.
 * Cached briefly to limit SQLite load on frequent scrapes.
 */
export async function buildPrometheusMetrics() {
  const now = Date.now()
  if (cache.body && now < cache.expiresAt) {
    return cache.body
  }

  const counts = await loadThreatCounts()
  const uptime = process.uptime().toFixed(3)
  const versionLabel = escapeLabelValue(version)

  const lines = [
    '# HELP qdbback_http_requests_total Total HTTP requests captured by the honeypot.',
    '# TYPE qdbback_http_requests_total counter',
    `qdbback_http_requests_total ${counts.total}`,
    '# HELP qdbback_http_requests_last24h HTTP requests captured in the last 24 hours.',
    '# TYPE qdbback_http_requests_last24h gauge',
    `qdbback_http_requests_last24h ${counts.last24h}`,
    '# HELP qdbback_http_requests_classified_total Requests with a non-unclassified threat tag.',
    '# TYPE qdbback_http_requests_classified_total counter',
    `qdbback_http_requests_classified_total ${counts.classified}`,
    '# HELP qdbback_http_requests_unclassified_total Requests without a threat classification.',
    '# TYPE qdbback_http_requests_unclassified_total gauge',
    `qdbback_http_requests_unclassified_total ${counts.unclassified}`,
    '# HELP qdbback_process_uptime_seconds Node.js process uptime.',
    '# TYPE qdbback_process_uptime_seconds gauge',
    `qdbback_process_uptime_seconds ${uptime}`,
    '# HELP qdbback_build_info Build metadata for the running qdbback process.',
    '# TYPE qdbback_build_info gauge',
    `qdbback_build_info{version="${versionLabel}"} 1`,
  ]

  cache = {
    expiresAt: now + CACHE_MS,
    body: `${lines.join('\n')}\n`,
  }
  return cache.body
}

/** Test helper — clears in-memory scrape cache. */
export function resetPrometheusMetricsCache() {
  cache = { expiresAt: 0, body: '' }
}
