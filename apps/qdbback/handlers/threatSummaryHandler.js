import { mimeTypes } from '../constants.js'
import { allDefault } from '../sqlite3.js'

/**
 * @type {import('../router').RequestListener}
 */
export const threatSummaryHandler = async (_req, res) => {
  const [[{ total }], byClass, [{ last24h }], [{ classified }]] = await Promise.all([
    allDefault('SELECT COUNT(*) AS total FROM httpRequests'),
    allDefault(`
SELECT classification AS tag, COUNT(*) AS count
FROM httpRequests
WHERE classification IS NOT NULL AND classification != '' AND classification != 'unclassified'
GROUP BY classification
ORDER BY count DESC
LIMIT 30`),
    allDefault(`
SELECT COUNT(*) AS last24h FROM httpRequests
WHERE timestamp >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-1 day')`),
    allDefault(`
SELECT COUNT(*) AS classified FROM httpRequests
WHERE classification IS NOT NULL AND classification != '' AND classification != 'unclassified'`),
  ])

  const payload = {
    total,
    last24h,
    classified,
    unclassified: total - classified,
    topTags: byClass,
  }

  res.writeHead(200, { 'Content-Type': mimeTypes.json }).end(JSON.stringify(payload))
}
