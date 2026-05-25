import { mimeTypes } from '../constants.js'
import { fetchThreatTimeseries } from '../services/threatTimeseries.js'

/**
 * @type {import('../router').RequestListener}
 */
export const threatTimeseriesHandler = async (_req, res) => {
  const payload = await fetchThreatTimeseries()
  res.writeHead(200, { 'Content-Type': mimeTypes.json }).end(JSON.stringify(payload))
}
