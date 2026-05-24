import { lookupServiceWithCache } from '../services/dns.js'
import { stringifyKeyPair, stringifyPlainMap, finalizeToJSON } from '../services/stringify.js'
import { mimeTypes, version } from '../constants.js'

/**
 * @type {import('../router').RequestListener}
 */
export const debugHandler = async (req, res) => {
  const json = finalizeToJSON([
    stringifyKeyPair('remoteAddress', req.socket.remoteAddress),
    stringifyKeyPair('remotePort', req.socket.remotePort),
    stringifyKeyPair('remoteFamily', req.socket.remoteFamily),
    stringifyKeyPair('remoteHostname', await lookupServiceWithCache(req.remoteIp, req.socket.remotePort)),
    stringifyKeyPair('localAddress', req.socket.localAddress),
    stringifyKeyPair('localPort', req.socket.localPort),
    stringifyKeyPair('headers', stringifyPlainMap(req.headers), true),
    stringifyKeyPair('httpVersion', req.httpVersion),
    stringifyKeyPair('trailers', stringifyPlainMap(req.trailers), true),
    stringifyKeyPair('url', req.url),
    stringifyKeyPair('version', version),
  ])
  res
    .writeHead(200, {
      'Content-Type': mimeTypes.json,
    })
    .write(json)
  res.end()
}
