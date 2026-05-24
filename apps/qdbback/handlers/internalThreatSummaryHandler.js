import { mimeTypes, INTERNAL_SCRAPE_IPS } from '../constants.js'
import { threatSummaryHandler } from './threatSummaryHandler.js'

/**
 * Read-only threat summary for in-cluster scrapers (Node Fleet / rs-observability-api).
 * Restricted to OCI K8s public egress IPs — see config/external-fleet/registry.yaml.
 *
 * @type {import('../router').RequestListener}
 */
export const internalThreatSummaryHandler = async (req, res) => {
  if (!INTERNAL_SCRAPE_IPS.has(req.remoteIp)) {
    res.writeHead(403, { 'Content-Type': mimeTypes.json }).end(JSON.stringify({ error: 'forbidden' }))
    return
  }

  await threatSummaryHandler(req, res)
}
