import { lookupServiceAndCacheIt } from './dns.js'
import { readFileSync } from 'fs'
import { join } from 'path'

const __dirname = decodeURIComponent(import.meta.url).split('file://').pop().split('/').slice(0, -1).join('/')
const { commitTitle, sha } = JSON.parse(readFileSync(join(__dirname, '../version.json')).toString())
const version = `${commitTitle} - ${sha}`

const stringifyKeyPair = (key, strValue, strObj = false) => {
  if (strValue === undefined) {
    return ''
  } else if (strValue === null) {
    return `"${key}":null`
  } else if (typeof strValue === 'string' && !strObj) {
    return `"${key}":"${strValue}"`
  } else {
    return `"${key}":${strValue}`
  }
}

const stringifyPlainMap = obj => {
  const keyPairs = Object.entries(obj).reduce((pv, [headerKey, headerValue]) => {
    const keyPair = stringifyKeyPair(headerKey, headerValue)
    if (keyPair) {
      pv.push(keyPair)
    }
    return pv
  }, [])
  return `{${keyPairs.join(',')}}`
}

/**
 * @type {import('./router').RequestListener}
 */
export const debugHandler = async (req, res) => {
  const keyPairs = [
    stringifyKeyPair('remoteAddress', req.socket.remoteAddress),
    stringifyKeyPair('remotePort', req.socket.remotePort),
    stringifyKeyPair('remoteFamily', req.socket.remoteFamily),
    stringifyKeyPair('remoteHostname', await lookupServiceAndCacheIt(req.remoteIp, req.socket.remotePort)),
    stringifyKeyPair('localAddress', req.socket.localAddress),
    stringifyKeyPair('localPort', req.socket.localPort),
    stringifyKeyPair('headers', stringifyPlainMap(req.headers), true),
    stringifyKeyPair('httpVersion', req.httpVersion),
    stringifyKeyPair('trailers', stringifyPlainMap(req.trailers), true),
    stringifyKeyPair('url', req.url),
    stringifyKeyPair('version', version)
  ]
  res
    .writeHead(200)
    .write(`{${keyPairs.join(',')}}`)
  res.end()
}

/**
 * @type {import('./router').RequestListener}
 */
export const indexHandler = (_, res) => {
  res.setHeader('Content-Type', 'text/html; charset=utf-8')
  res
    .writeHead(200)
    .write('<html><h1>Aprecie este maravilhoso pudim</h1><img src="pudim.png"></html>')
  res.end()
}
