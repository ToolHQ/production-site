import { logger } from '../logger.js'
import { parseBody } from '../services/bodyParser.js'

/**
 * @type {import('../router').RequestListener}
 */
export const cspReportsHandler = async (req, res) => {
  try {
    const cspReport = await parseBody(req)
    logger.info('cspReport INFO', cspReport)
    res.writeHead(200)
  } catch (err) {
    logger.error('cspReport ERROR', { cause: err.message, stack: err.stack, body: req.body })
    res.writeHead(500)
  }
  res.end()
}
