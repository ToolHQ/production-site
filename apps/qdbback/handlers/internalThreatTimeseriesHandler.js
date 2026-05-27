import { mimeTypes, INTERNAL_SCRAPE_IPS } from '../constants.js'
import { threatTimeseriesHandler } from './threatTimeseriesHandler.js'

/**
 * Hourly/daily request buckets for Node Fleet sparklines (rs-observability-api scrape).
 *
 * @type {import('../router').RequestListener}
 */
export const internalThreatTimeseriesHandler = async (req, res) => {
  if (!INTERNAL_SCRAPE_IPS.has(req.remoteIp)) {
    res.writeHead(403, { 'Content-Type': mimeTypes.json }).end(JSON.stringify({ error: 'forbidden' }))
    return
  }

  await threatTimeseriesHandler(req, res)
}
