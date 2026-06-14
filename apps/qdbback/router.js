/* eslint-disable security/detect-non-literal-regexp */
import { METHODS } from 'http'
import { log, logger } from './logger.js'
import { lookupServiceWithCache } from './services/dns.js'
import { classifyRequest } from './services/classifyRequest.js'
import { lookupCountry } from './services/geoip.js'
import { runDefault } from './sqlite3.js'
import { cspDefaultHeader } from './config.js'

/**
 * @return {Map<String, Boolean>}
 */
const getMethodMap = (defaultValue) => {
  const map = new Map()
  for (const method of METHODS) {
    map.set(method, defaultValue)
  }
  return map
}

/**
 * @typedef {Object} RequestListenerExtraProperties
 * @property {String} path
 * @property {{ [key: string]: string }} query
 * @property {{ [key: string]: string }} [params]
 * @property {String} remoteIp
 */

/**
 * @callback RequestListener
 * @param {import('http').IncomingMessage & RequestListenerExtraProperties} req
 * @param {import('http').ServerResponse} res
 */

const forbiddenProperties = Object.getOwnPropertyNames(Object.prototype)

const buildQueryParameters = (queryEntries) => {
  const queryObj = {}
  for (const [key, value] of queryEntries) {
    let curKey = ''
    let pointer = queryObj
    for (const charKey of key) {
      if (charKey === '[' && !forbiddenProperties.includes(curKey)) {
        // eslint-disable-next-line security/detect-object-injection
        pointer[curKey] = {}
        // eslint-disable-next-line security/detect-object-injection
        pointer = pointer[curKey]
        curKey = ''
      } else if (charKey !== ']') {
        curKey += charKey
      }
    }
    // eslint-disable-next-line security/detect-object-injection
    if (!forbiddenProperties.includes(curKey)) pointer[curKey] = value
  }
  return queryObj
}

/**
 * @param {import('http').IncomingMessage} req
 */
export const buildReq = (req) => {
  const reqUrl = new URL(req.url, 'http://127.0.0.1/')
  const path = reqUrl.pathname
  const remoteIp = req.socket.remoteAddress?.replace('::ffff:', '')
  req.path = path
  req.query = buildQueryParameters(reqUrl.searchParams.entries())
  req.remoteIp = remoteIp
  return { path, remoteIp }
}

/**
 * @param {String} route
 * @param {String} method
 */
const getRouteRegexStr = (route, method) => {
  // eslint-disable-next-line no-param-reassign
  route = route.replace(/\\/g, '\\\\').replace(/\./g, '\\.').replace(/\+/g, '\\+').replace(/\*/g, '.*')
  const paramsGroups = route.split(':')
  let regexStr = `^${paramsGroups[0]}`
  const afterParamsGroup = paramsGroups.slice(1)
  for (const paramsGroup of afterParamsGroup) {
    const barPosition = paramsGroup.indexOf('/')
    regexStr += barPosition > -1
      ? `(?<${paramsGroup.slice(0, barPosition)}>\\w+)${paramsGroup.slice(barPosition)}`
      : `(?<${paramsGroup}>\\w+)`
  }
  regexStr += '$'
  log('Route registered', { method, route, regexStr })
  return regexStr
}

// export class SimpleJSONStreamer extends Readable {
//   constructor(opt) {
//     super(opt)
//     this._inputArr = Array.isArray(opt.inputArr) ? opt.inputArr : []
//     this._lastPos = this._inputArr.length - 1
//     this._index = -1
//   }

//   static parseRow(row) {
//     return JSON.stringify(row)
//   }

//   _read() {
//     const i = this._index++
//     if (i === -1) {
//       this.push(Buffer.from('[', 'utf-8'))
//     } else if (i < this._lastPos) {
//       this.push(Buffer.from(`${this.parseRow(this._inputArr[i])},`, 'utf-8'))
//     } else if (i === this._lastPos) {
//       this.push(Buffer.from(this.parseRow(this._inputArr[i]), 'utf-8'))
//     } else {
//       this.push(Buffer.from(']', 'utf-8'))
//       this.push(null)
//     }
//   }
// }

/**
 * Set some standardized Browser security headers
 * @param {import('http').ServerResponse} res
 */
const setSecurityHeaders = (res) => {
  res.setHeader('Server', 'PuddingServer/1.5.65')
  // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Strict-Transport-Security
  // Add to https://hstspreload.org/
  res.setHeader('Strict-Transport-Security', 'max-age=63072000; includeSubDomains; preload')
  // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Content-Type-Options
  res.setHeader('X-Content-Type-Options', 'nosniff')
  // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Frame-Options
  res.setHeader('X-Frame-Options', 'DENY')
  // TODO: Check for other sources
  // https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP
  res.setHeader('Content-Security-Policy', cspDefaultHeader)
  // X-XSS-Protection: 1; mode=block
  res.setHeader('X-XSS-Protection', '1; mode=block')
}
export class Router {
  /**
   * @param {RequestListener} defaultHandler
   */
  constructor(defaultHandler = (_, res) => {
    res.writeHead(404)
    res.end()
  }, securityValidate = () => false) {
    this.defaultHandler = defaultHandler
    this.securityValidate = securityValidate
    /**
     * @type {[RegExp, Map<String, Boolean>, RequestListener[]][]} routes
     */
    this.routes = []
  }

  /**
   * @param {String} route
   * @param {RequestListener[]} listeners
   */
  route(route, ...listeners) {
    this.routes.push([new RegExp(getRouteRegexStr(route, '*'), 'i'), getMethodMap(true), listeners])
    return this
  }

  /**
   * @param {String} route
   * @param {RequestListener[]} listeners
   */
  get(route, ...listeners) {
    const methodMap = getMethodMap(false)
    methodMap.set('HEAD', true)
    methodMap.set('GET', true)
    this.routes.push([new RegExp(getRouteRegexStr(route, 'GET'), 'i'), methodMap, listeners])
    return this
  }

  /**
   * @param {String} route
   * @param {RequestListener[]} listeners
   */
  post(route, ...listeners) {
    const methodMap = getMethodMap(false)
    methodMap.set('HEAD', true)
    methodMap.set('POST', true)
    this.routes.push([new RegExp(getRouteRegexStr(route, 'POST'), 'i'), methodMap, listeners])
    return this
  }

  /**
   * @param {String} route
   * @param {RequestListener[]} listeners
   */
  put(route, ...listeners) {
    const methodMap = getMethodMap(false)
    methodMap.set('HEAD', true)
    methodMap.set('PUT', true)
    this.routes.push([new RegExp(getRouteRegexStr(route, 'PUT'), 'i'), methodMap, listeners])
    return this
  }

  /**
   * @param {String} route
   * @param {RequestListener[]} listeners
   */
  patch(route, ...listeners) {
    const methodMap = getMethodMap(false)
    methodMap.set('HEAD', true)
    methodMap.set('PATCH', true)
    this.routes.push([new RegExp(getRouteRegexStr(route, 'PATCH'), 'i'), methodMap, listeners])
    return this
  }

  /**
   * @param {String} route
   * @param {RequestListener[]} listeners
   */
  delete(route, ...listeners) {
    const methodMap = getMethodMap(false)
    methodMap.set('HEAD', true)
    methodMap.set('DELETE', true)
    this.routes.push([new RegExp(getRouteRegexStr(route, 'DELETE'), 'i'), methodMap, listeners])
    return this
  }

  /**
   * @param {import('http').IncomingMessage} req
   * @param {import('http').ServerResponse} res
   */
  async handle(req, res) {
    // Sets to measure time & log request
    const hrTimeStart = process.hrtime()
    setSecurityHeaders(res)
    const { path, remoteIp } = buildReq(req)

    res.on('finish', async () => {
      const hrTimeElapsed = process.hrtime(hrTimeStart)
      const timeElapsedFormatted = (hrTimeElapsed[0] * 1000 + hrTimeElapsed[1] / 1000000).toFixed(3)
      const timeElapsed = Number(timeElapsedFormatted.replace('.', ''))
      const remoteHostname = await lookupServiceWithCache(req.remoteIp, req.socket.remotePort)
      const userAgent = req.headers['user-agent']
      logger.info('Request received', {
        method: req.method,
        path,
        timeElapsed: `${timeElapsedFormatted}ms`,
        remoteIp,
        remoteHostname,
        userAgent,
        statusCode: res.statusCode,
      })
      if (remoteIp !== '127.0.0.1') {
        const classification = classifyRequest({
          path,
          method: req.method,
          userAgent,
          statusCode: res.statusCode,
        })
        const country = lookupCountry(remoteIp)
        await runDefault(
          'insert into httpRequests (timestamp, method, path, timeElapsed, remoteIp, remoteHostname, statusCode, userAgent, body, headers, country, classification) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            new Date().toISOString(),
            req.method,
            path,
            timeElapsed,
            remoteIp,
            remoteHostname,
            res.statusCode,
            userAgent,
            null,
            JSON.stringify(req.headers),
            country,
            classification,
          ],
        )
      }
    })

    const securityValidateError = this.securityValidate(req, res)
    if (securityValidateError) {
      res.statusCode = 404
      return res.end()
    }

    for (const [routePath, methodMap, listeners] of this.routes) {
      if (methodMap.get(req.method)) {
        const found = path.match(routePath)
        if (found) {
          if (found.groups) req.params = found.groups
          for (const listener of listeners) {
            // eslint-disable-next-line no-await-in-loop
            if (await listener(req, res)) {
              return null
            }
          }
          return null
        }
      }
    }
    return this.defaultHandler(req, res)
  }
}
