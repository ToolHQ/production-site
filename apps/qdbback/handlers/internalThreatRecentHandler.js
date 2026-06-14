import { mimeTypes, INTERNAL_SCRAPE_IPS } from '../constants.js'
import { allDefault } from '../sqlite3.js'

/**
 * Read-only recent requests for in-cluster scrapers (Node Fleet / rs-observability-api).
 * Restricted to OCI K8s public egress IPs.
 *
 * @type {import('../router').RequestListener}
 */
export const internalThreatRecentHandler = async (req, res) => {
  if (!INTERNAL_SCRAPE_IPS.has(req.remoteIp)) {
    res.writeHead(403, { 'Content-Type': mimeTypes.json }).end(JSON.stringify({ error: 'forbidden' }))
    return
  }

  const recent = await allDefault(`
SELECT
  timestamp,
  method,
  path,
  remoteIp as ip,
  userAgent,
  classification as tag
FROM httpRequests
ORDER BY id DESC
LIMIT 20
  `)

  // Convert "unclassified" or null tags to empty string for consistency
  const payload = recent.map(r => ({
    timestamp: r.timestamp,
    method: r.method,
    path: r.path,
    ip: r.ip,
    userAgent: r.userAgent || '',
    tag: r.tag === 'unclassified' || !r.tag ? '' : r.tag,
  }))

  res.writeHead(200, { 'Content-Type': mimeTypes.json }).end(JSON.stringify(payload))
}
