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

/** @type {import('./productionHttpRouter.js').getRouter} */
let getRouter

describe('routers/productionHttpRouter.js', () => {
  beforeAll(async () => {
    getRouter = (await import('./productionHttpRouter.js')).getRouter
    jest.useFakeTimers()
  })

  beforeEach(async () => {
    jest.setSystemTime(Date.parse(FIXED_SYSTEM_TIME))
  })

  afterAll(() => {
    jest.useRealTimers()
  })

  test('Should handle request properly redirecting to same location with https', async () => {
    const { loggerInfoFn, runDefaultFn } = reloadMock()
    const router = getRouter()
    expect(loggerInfoFn).toBeCalledTimes(0)
    const resMock = getResMock(jest, {
      req: {
        url: '/method/123?a=abc&b=456',
        headers: {
          host: 'www.cursosgratis.com',
        },
      },
    })
    router.handle(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(301)
    expect(resMock.headers).toStrictEqual({
      // eslint-disable-next-line max-len
      'Content-Security-Policy': "default-src 'self'; style-src https://fonts.googleapis.com 'unsafe-inline' 'self'; font-src https://fonts.gstatic.com 'self'; report-uri /internal/csp-reports",
      Location: 'https://www.cursosgratis.com/method/123?a=abc&b=456',
      Server: 'PuddingServer/1.5.65',
      'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'DENY',
      'X-XSS-Protection': '1; mode=block',
    })
    expect(resMock.body).toBe('')
    jest.advanceTimersByTime(5)
    resMock.res.emit('finish')
    await resMock.finishPromise
    expect(runDefaultFn).toBeCalled()
    expect(runDefaultFn.mock.calls).toEqual([
      [
        'insert into httpRequests (timestamp, method, path, timeElapsed, remoteIp, remoteHostname, statusCode, userAgent, body, headers, classification) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          '1994-04-03T15:00:00.005Z',
          'GET',
          '/method/123',
          5000,
          undefined,
          '201-26-160-146.dial-up.telesp.net.br',
          301,
          undefined,
          null,
          JSON.stringify({ host: 'www.cursosgratis.com' }),
          'unclassified',
        ],
      ],
    ])
  })
})
