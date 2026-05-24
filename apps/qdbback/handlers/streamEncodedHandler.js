import { pipeline } from 'stream'

import { mimeTypes, cacheConstants } from '../constants.js'
import { logger } from '../logger.js'

import { getEncoding, getEncoder } from '../services/encoding.js'

/**
 * Gets a route handler with encoding support.
 * The inner requestListener must return or resolves a stream or array of streams with the data transformations
 * @param {import('../router').RequestListener} requestListener
 * @param {Boolean} propagateErrors
 * @returns {import('../router').RequestListener}
 */
export const getStreamHandler = (requestListener, propagateErrors = false) => async (req, res) => {
  try {
    const encoderInfo = getEncoding(req.headers['accept-encoding'])
    if (!encoderInfo) {
      res.statusCode = 406
      res.setHeader('Content-Type', 'application/json')
      res.end('{"error":"Encoding Not Supported"}')
      return
    }
    const inputStreams = await requestListener(req, res)
    if (res.headersSent) return
    const initialStreams = Array.isArray(inputStreams) ? inputStreams : [inputStreams]
    res.statusCode = 200
    res.setHeader('Content-Type', mimeTypes.json)
    res.setHeader('Content-Encoding', encoderInfo)
    res.setHeader('Cache-Control', cacheConstants.policies.noStore)
    pipeline(...initialStreams, getEncoder(encoderInfo), res, (err) => {
      if (err) {
        logger.error(`${req.path} Pipeline ERROR`, {
          name: err.name, message: err.message, stack: err.stack, code: err.code,
        })
      }
    })
  } catch (err) {
    logger.error(`${req.path} Handler ERROR`, { name: err.name, message: err.message, stack: err.stack })
    const statusCode = err.statusCode || 500
    res.writeHead(statusCode, {
      'Content-Type': mimeTypes.json,
      'Content-Encoding': 'identity',
      'Cache-Control': cacheConstants.policies.noStore,
    })
    const message = propagateErrors ? err.message : 'Internal Server Error'
    res.end(JSON.stringify({ message }))
  }
}
