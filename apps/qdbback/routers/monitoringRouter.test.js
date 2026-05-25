import { Readable } from 'stream'
import zlib from 'zlib'

import {
  afterAll,
  beforeAll,
  beforeEach,
  describe,
  expect,
  jest,
  test,
} from '@jest/globals'

import { readFileAsync, createReadStream } from '../services/fs.js'

import { getResMock } from '../testingHelpers.js'

const FIXED_SYSTEM_TIME = '1994-04-03T15:00:00.000Z'

const initMock = () => {
  const defaultServiceName = '201-26-160-146.dial-up.telesp.net.br'

  const loggerInfoFn = jest.fn()
  const loggerErrorFn = jest.fn()

  // eslint-disable-next-line no-unused-vars
  const lookupServiceWithCacheFn = jest.fn(async (remoteIp, remotePort) => defaultServiceName)

  const runDefaultFn = jest.fn()
  const allDefaultFn = jest.fn(async () => null)
  const getStreamFromAnySQLFn = jest.fn()
  const getStreamFromSQLFn = jest.fn(() => Readable.from(JSON.stringify({})))

  jest.mockModule('../logger.js', () => ({
    logger: {
      info: loggerInfoFn,
      error: loggerErrorFn,
    },
    log: loggerInfoFn,
  }))

  jest.mockModule('../services/dns.js', () => ({
    lookupServiceWithCache: lookupServiceWithCacheFn,
  }))

  jest.mockModule('../services/geoip.js', () => ({
    lookupCountry: jest.fn(() => null),
  }))

  jest.mockModule('../services/monitorAuth.js', () => ({
    monitorAuthMiddleware: jest.fn(() => false),
  }))

  const fileLastModifiedFn = jest.fn(() => 123)
  jest.mockModule('../services/fs.js', () => ({
    createReadStream,
    fileLastModified: fileLastModifiedFn,
  }))

  jest.mockModule('../sqlite3.js', () => ({
    runDefault: runDefaultFn,
    allDefault: allDefaultFn,
    getStreamFromAnySQL: getStreamFromAnySQLFn,
    getStreamFromSQL: getStreamFromSQLFn,
  }))

  const reloadMock = ({
    allDefaultResult,
    streamSQLResult = {},
  }) => {
    loggerInfoFn.mockReset()
    loggerErrorFn.mockReset()
    lookupServiceWithCacheFn.mockReset().mockImplementation(async () => defaultServiceName)
    runDefaultFn.mockReset()
    allDefaultFn.mockReset().mockImplementation(async () => allDefaultResult)
    getStreamFromAnySQLFn.mockReset().mockImplementation(() => Readable.from(JSON.stringify(streamSQLResult)))
    getStreamFromSQLFn.mockReset().mockImplementation(() => Readable.from(JSON.stringify(streamSQLResult)))

    return {
      loggerInfoFn,
      loggerErrorFn,
      lookupServiceWithCacheFn,
      runDefaultFn,
      allDefaultFn,
      getStreamFromAnySQLFn,
      getStreamFromSQLFn,
    }
  }
  return {
    reloadMock,
  }
}

const { reloadMock } = initMock()

const getExpectedHeaders = ({
  ...extraHeaders
} = {
}) => JSON.parse(JSON.stringify({
  'Content-Type': 'application/json',
  // eslint-disable-next-line max-len
  'Content-Security-Policy': "default-src 'self'; style-src https://fonts.googleapis.com 'unsafe-inline' 'self'; font-src https://fonts.gstatic.com 'self'; report-uri /internal/csp-reports",
  Server: 'PuddingServer/1.5.65',
  'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'X-XSS-Protection': '1; mode=block',
  ...extraHeaders,
}))

const getExpectedRouteRegisteredLogs = () => {
  global.c = 1 + 1
  return [
    [
      'Route registered',
      { method: 'GET', regexStr: '^/$', route: '/' },
    ],
    [
      'Route registered',
      { method: 'GET', regexStr: '^/noscript\\.html$', route: '/noscript\\.html' },
    ],
    [
      'Route registered',
      {
        method: 'GET',
        regexStr: '^/monitor/(index\\.html)?$',
        route: '/monitor/(index\\.html)?',
      },
    ],
    [
      'Route registered',
      {
        method: 'GET',
        regexStr: '^/monitor/(requests|logs|sql|status)$',
        route: '/monitor/(requests|logs|sql|status)',
      },
    ],
    [
      'Route registered',
      {
        method: 'POST',
        regexStr: '^/internal/csp-reports$',
        route: '/internal/csp-reports',
      },
    ],
    [
      'Route registered',
      {
        method: 'GET',
        regexStr: '^/monitor$',
        route: '/monitor',
      },
    ],
    [
      'Route registered',
      {
        method: 'GET',
        regexStr: '^/index\\.js$',
        route: '/index\\.js',
      },
    ],
    [
      'Route registered',
      {
        method: 'GET',
        regexStr: '^/style\\.css$',
        route: '/style\\.css',
      },
    ],
    [
      'Route registered',
      {
        method: 'GET',
        regexStr: '^/favicon\\.ico$',
        route: '/favicon\\.ico',
      },
    ],
    [
      'Route registered',
      {
        method: 'GET',
        regexStr: '^/accept-languages$',
        route: '/accept-languages',
      },
    ],
    [
      'Route registered',
      {
        method: 'GET',
        regexStr: '^/api/monitor/requests$',
        route: '/api/monitor/requests',
      },
    ],
    [
      'Route registered',
      {
        method: 'GET',
        regexStr: '^/api/monitor/logs$',
        route: '/api/monitor/logs',
      },
    ],
    [
      'Route registered',
      {
        method: 'POST',
        regexStr: '^/api/monitor/sql$',
        route: '/api/monitor/sql',
      },
    ],
    [
      'Route registered',
      {
        method: 'GET',
        regexStr: '^/api/monitor/status$',
        route: '/api/monitor/status',
      },
    ],
    [
      'Route registered',
      {
        method: 'GET',
        regexStr: '^/api/monitor/threats$',
        route: '/api/monitor/threats',
      },
    ],
  ]
}

/** @type {import('./monitoringRouter').getRouter} */
let getRouter

const socket = {
  remoteAddress: '201.26.160.146',
  remotePort: 8080,
}

describe('routers/monitoringRouter.js', () => {
  beforeAll(async () => {
    getRouter = (await import('./monitoringRouter.js')).getRouter
    jest.useFakeTimers()
  })

  beforeEach(async () => {
    jest.setSystemTime(Date.parse(FIXED_SYSTEM_TIME))
  })

  afterAll(() => {
    jest.useRealTimers()
  })

  describe('GET /', () => {
    test('Should "GET /" redirect to /monitor/requests', async () => {
      const {
        loggerInfoFn,
        loggerErrorFn,
        lookupServiceWithCacheFn,
        runDefaultFn,
        allDefaultFn,
        getStreamFromAnySQLFn,
        getStreamFromSQLFn,
      } = reloadMock({})

      const router = getRouter()
      const headers = {
        'accept-encoding': 'gzip, deflate, br',
        'user-agent': 'abc',
      }
      const resMock = getResMock(jest, {
        req: {
          method: 'GET',
          url: '/',
          headers,
          socket,
        },
      })

      router.handle(resMock.req, resMock.res)
      jest.advanceTimersByTime(5)
      resMock.res.emit('finish')
      await resMock.finishPromise

      expect(resMock.statusCode).toBe(301)
      expect(resMock.headers).toStrictEqual(getExpectedHeaders({
        'Content-Type': undefined,
        Location: '/monitor/requests',
      }))
      expect(resMock.body).toBe('')
      expect(loggerInfoFn).toBeCalled()
      expect(loggerInfoFn.mock.calls).toEqual([
        ...getExpectedRouteRegisteredLogs(),
        [
          'Request received',
          {
            method: 'GET',
            path: '/',
            remoteHostname: '201-26-160-146.dial-up.telesp.net.br',
            remoteIp: socket.remoteAddress,
            statusCode: 301,
            timeElapsed: '5.000ms',
            userAgent: headers['user-agent'],
          },
        ],
      ])
      expect(loggerErrorFn).not.toBeCalled()
      expect(lookupServiceWithCacheFn).toBeCalledWith(socket.remoteAddress, socket.remotePort)
      expect(allDefaultFn).not.toBeCalled()
      expect(getStreamFromAnySQLFn).not.toBeCalled()
      expect(getStreamFromSQLFn).not.toBeCalled()
      expect(runDefaultFn).toBeCalled()
      expect(runDefaultFn.mock.calls).toEqual([
        [
          'insert into httpRequests (timestamp, method, path, timeElapsed, remoteIp, remoteHostname, statusCode, userAgent, body, headers, country, classification) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            '1994-04-03T15:00:00.005Z',
            'GET',
            '/',
            5000,
            socket.remoteAddress,
            '201-26-160-146.dial-up.telesp.net.br',
            301,
            'abc',
            null,
            JSON.stringify(headers),
            null,
            'probe:root',
          ],
        ],
      ])
    })
  })

  describe('GET /noscript.html', () => {
    test('Should "GET /noscript.html" return noscript.html properly', async () => {
      reloadMock({})

      const router = getRouter()
      const headers = {
        'accept-encoding': 'gzip, deflate, br',
        'user-agent': 'abc',
      }
      const resMock = getResMock(jest, {
        req: {
          method: 'GET',
          url: '/noscript.html',
          headers,
          socket,
        },
      })

      router.handle(resMock.req, resMock.res)
      jest.advanceTimersByTime(5)
      await resMock.endPromise
      resMock.res.emit('finish')
      await resMock.finishPromise

      expect(resMock.statusCode).toBe(200)
      expect(resMock.headers).toStrictEqual(getExpectedHeaders({
        'Cache-Control': 'no-cache',
        'Content-Encoding': 'gzip',
        'Content-Type': 'text/html; charset=utf-8',
        ETag: '40bd001563085fc35165329ea1ff5c5ecbdbbeef',
        Expires: 'Sun, 10 Apr 1994 15:00:00 GMT',
        Vary: 'ETag',
      }))
      const htmlContent = await readFileAsync('./noscript.html')
      expect(resMock.body).toBe(zlib.gzipSync(htmlContent).toString())
    })
  })

  describe('GET /monitor/(index.html)?', () => {
    test('Should "GET /monitor/" redirect to /monitor/requests', async () => {
      reloadMock({})

      const router = getRouter()
      const headers = {
        'accept-encoding': 'gzip, deflate, br',
        'user-agent': 'abc',
      }
      const resMock = getResMock(jest, {
        req: {
          method: 'GET',
          url: '/monitor/',
          headers,
          socket,
        },
      })

      router.handle(resMock.req, resMock.res)
      jest.advanceTimersByTime(5)
      resMock.res.emit('finish')
      await resMock.finishPromise

      expect(resMock.statusCode).toBe(301)
      expect(resMock.headers).toStrictEqual(getExpectedHeaders({
        'Content-Type': undefined,
        Location: '/monitor/requests',
      }))
      expect(resMock.body).toBe('')
    })

    test('Should "GET /monitor/index.html" redirect to /monitor/requests', async () => {
      reloadMock({})

      const router = getRouter()
      const headers = {
        'accept-encoding': 'gzip, deflate, br',
        'user-agent': 'abc',
      }
      const resMock = getResMock(jest, {
        req: {
          method: 'GET',
          url: '/monitor/index.html',
          headers,
          socket,
        },
      })

      router.handle(resMock.req, resMock.res)
      jest.advanceTimersByTime(5)
      resMock.res.emit('finish')
      await resMock.finishPromise

      expect(resMock.statusCode).toBe(301)
      expect(resMock.headers).toStrictEqual(getExpectedHeaders({
        'Content-Type': undefined,
        Location: '/monitor/requests',
      }))
      expect(resMock.body).toBe('')
    })
  })

  // test('Should handle "GET /.env" request with default 404 response', async () => {
  //   const { runDefaultFn } = reloadMock()
  //   const router = getRouter()
  //   const resMock = getResMock(jest, {
  //     req: {
  //       method: 'GET',
  //       url: '/.env',
  //       headers: {
  //         'Content-Encoding': 'gzip',
  //       },
  //     },
  //   })
  //   router.handle(resMock.req, resMock.res)
  //   expect(resMock.statusCode).toBe(404)
  //   expect(resMock.headers).toStrictEqual({
  //     // eslint-disable-next-line max-len
  //     'Content-Security-Policy': "default-src
  // 'self'; style-src https://fonts.googleapis.com 'unsafe-inline' 'self'; font-src https://fonts.gstatic.com 'self'; report-uri /internal/csp-reports",
  //     'Content-Type': 'text/html; charset=utf-8',
  //     Server: 'PuddingServer/1.5.65',
  //     'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
  //     'X-Content-Type-Options': 'nosniff',
  //     'X-Frame-Options': 'DENY',
  //     'X-XSS-Protection': '1; mode=block',
  //   })
  //   expect(resMock.body).toBe('<html>The resource you are looking are not available</html>')
  //   jest.advanceTimersByTime(5)
  //   resMock.res.emit('finish')
  //   await resMock.finishPromise
  //   expect(runDefaultFn).toBeCalled()
  //   expect(runDefaultFn.mock.calls).toEqual([
  //     [
  //       'insert into httpRequests (timestamp, method, path, timeElapsed, remoteIp, remoteHostname, statusCode, userAgent, body, headers) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
  //       [
  //         '1994-04-03T15:00:00.005Z',
  //         'GET',
  //         '/.env',
  //         5000,
  //         undefined,
  //         '201-26-160-146.dial-up.telesp.net.br',
  //         404,
  //         undefined,
  //         null,
  //         JSON.stringify({ 'Content-Encoding': 'gzip' }),
  //       ],
  //     ],
  //   ])
  // })
})
