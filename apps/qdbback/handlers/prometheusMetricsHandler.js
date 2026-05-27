import { INTERNAL_SCRAPE_IPS } from '../constants.js'
import { buildPrometheusMetrics } from '../services/qdbbackMetrics.js'

const PROMETHEUS_CONTENT_TYPE = 'text/plain; version=0.0.4; charset=utf-8'

/**
 * Prometheus scrape endpoint for in-cluster collectors (OCI K8s egress allowlist).
 *
 * @type {import('../router').RequestListener}
 */
export const prometheusMetricsHandler = async (req, res) => {
  if (!INTERNAL_SCRAPE_IPS.has(req.remoteIp)) {
    res.writeHead(403, { 'Content-Type': PROMETHEUS_CONTENT_TYPE }).end('forbidden\n')
    return
  }

  const body = await buildPrometheusMetrics()
  res.writeHead(200, { 'Content-Type': PROMETHEUS_CONTENT_TYPE }).end(body)
}
