import { mimeTypes } from '../constants.js'
import { parseAcceptLanguageHeader } from '../services/parseAcceptLanguageHeader.js'

/**
 * @type {import('../router').RequestListener}
 */
export const acceptLanguageHandler = (req, res) => res
  .writeHead(200, {
    'Content-Type': mimeTypes.json,
  })
  .end(JSON.stringify({ languages: parseAcceptLanguageHeader(req.headers['accept-language']) }))
