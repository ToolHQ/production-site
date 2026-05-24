import {
  afterAll,
  beforeAll,
  beforeEach,
  describe,
  expect,
  jest,
  test,
} from '@jest/globals'

import { getResMock } from '../testingHelpers.js'

const FIXED_SYSTEM_TIME = '1994-04-03T15:00:00.000Z'

const initMock = () => {
  const defaultServiceName = '201-26-160-146.dial-up.telesp.net.br'

  const loggerInfoFn = jest.fn()
  const loggerErrorFn = jest.fn()

  // eslint-disable-next-line no-unused-vars
  const lookupServiceWithCacheFn = jest.fn(async (remoteIp, remotePort) => defaultServiceName)

  const runDefaultFn = jest.fn()

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

  jest.mockModule('../sqlite3.js', () => ({
    runDefault: runDefaultFn,
  }))

  const reloadMock = () => {
    loggerInfoFn.mockReset()
    loggerErrorFn.mockReset()
    lookupServiceWithCacheFn.mockReset().mockImplementation(async () => defaultServiceName)
    runDefaultFn.mockReset()
    return {
      loggerInfoFn,
      loggerErrorFn,
      lookupServiceWithCacheFn,
      runDefaultFn,
    }
  }
  return {
    reloadMock,
  }
}

const { reloadMock } = initMock()

/** @type {import('./mainRouter').getRouter} */
let getRouter

describe('routers/mainRouter.js', () => {
  beforeAll(async () => {
    getRouter = (await import('./mainRouter')).getRouter
    jest.useFakeTimers()
  })

  beforeEach(async () => {
    jest.setSystemTime(Date.parse(FIXED_SYSTEM_TIME))
  })

  afterAll(() => {
    jest.useRealTimers()
  })

  test('Should handle "GET /" request with home response', async () => {
    const { runDefaultFn } = reloadMock()
    const router = getRouter()
    const resMock = getResMock(jest, {
      req: {
        method: 'GET',
        url: '/',
        headers: {
          'Content-Encoding': 'gzip',
        },
      },
    })
    router.handle(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(200)
    expect(resMock.headers).toStrictEqual({
      // eslint-disable-next-line max-len
      'Content-Security-Policy': "default-src 'self'; style-src https://fonts.googleapis.com 'unsafe-inline' 'self'; font-src https://fonts.gstatic.com 'self'; report-uri /internal/csp-reports",
      'Content-Type': 'text/html; charset=utf-8',
      Server: 'PuddingServer/1.5.65',
      'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'DENY',
      'X-XSS-Protection': '1; mode=block',
    })
    expect(resMock.body).toBe('<html><h1>Aprecie este maravilhoso pudim</h1><img src="pudim.png"></html>')
    jest.advanceTimersByTime(5)
    resMock.res.emit('finish')
    await resMock.finishPromise
    expect(runDefaultFn).toBeCalled()
    expect(runDefaultFn.mock.calls).toEqual([
      [
        'insert into httpRequests (timestamp, method, path, timeElapsed, remoteIp, remoteHostname, statusCode, userAgent, body, headers, country, classification) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          '1994-04-03T15:00:00.005Z',
          'GET',
          '/',
          5000,
          undefined,
          '201-26-160-146.dial-up.telesp.net.br',
          200,
          undefined,
          null,
          JSON.stringify({ 'Content-Encoding': 'gzip' }),
          null,
          'probe:root',
        ],
      ],
    ])
  })

  test('Should handle "GET /.env" request with default 404 response', async () => {
    const { runDefaultFn } = reloadMock()
    const router = getRouter()
    const resMock = getResMock(jest, {
      req: {
        method: 'GET',
        url: '/.env',
        headers: {
          'Content-Encoding': 'gzip',
        },
      },
    })
    router.handle(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(404)
    expect(resMock.headers).toStrictEqual({
      // eslint-disable-next-line max-len
      'Content-Security-Policy': "default-src 'self'; style-src https://fonts.googleapis.com 'unsafe-inline' 'self'; font-src https://fonts.gstatic.com 'self'; report-uri /internal/csp-reports",
      'Content-Type': 'text/html; charset=utf-8',
      Server: 'PuddingServer/1.5.65',
      'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'DENY',
      'X-XSS-Protection': '1; mode=block',
    })
    expect(resMock.body).toBe('<html>The resource you are looking are not available</html>')
    jest.advanceTimersByTime(5)
    resMock.res.emit('finish')
    await resMock.finishPromise
    expect(runDefaultFn).toBeCalled()
    expect(runDefaultFn.mock.calls).toEqual([
      [
        'insert into httpRequests (timestamp, method, path, timeElapsed, remoteIp, remoteHostname, statusCode, userAgent, body, headers, country, classification) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          '1994-04-03T15:00:00.005Z',
          'GET',
          '/.env',
          5000,
          undefined,
          '201-26-160-146.dial-up.telesp.net.br',
          404,
          undefined,
          null,
          JSON.stringify({ 'Content-Encoding': 'gzip' }),
          null,
          'env-leak',
        ],
      ],
    ])
  })
})
