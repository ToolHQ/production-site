import {
  afterAll,
  beforeAll,
  beforeEach,
  describe,
  expect,
  jest,
  test,
} from '@jest/globals'

import { getResMock } from './testingHelpers.js'

const FIXED_SYSTEM_TIME = '1994-04-03T15:00:00.000Z'

const initMock = () => {
  const defaultServiceName = '201-26-160-146.dial-up.telesp.net.br'

  const loggerInfoFn = jest.fn()
  const loggerErrorFn = jest.fn()

  // eslint-disable-next-line no-unused-vars
  const lookupServiceWithCacheFn = jest.fn(async (remoteIp, remotePort) => defaultServiceName)

  const runDefaultFn = jest.fn()

  jest.mockModule('./logger.js', () => ({
    logger: {
      info: loggerInfoFn,
      error: loggerErrorFn,
    },
    log: loggerInfoFn,
  }))

  jest.mockModule('./services/dns.js', () => ({
    lookupServiceWithCache: lookupServiceWithCacheFn,
  }))

  jest.mockModule('./sqlite3.js', () => ({
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

/** @type {import('./router.js')} */
let RouterModule

describe('router.js', () => {
  beforeAll(async () => {
    RouterModule = await import('./router.js')
    jest.useFakeTimers()
  })

  beforeEach(async () => {
    jest.setSystemTime(Date.parse(FIXED_SYSTEM_TIME))
  })

  afterAll(() => {
    jest.useRealTimers()
  })

  test('Should register get/post/put/patch/delete routes properly', async () => {
    const { loggerInfoFn } = reloadMock()
    const router = new RouterModule.Router()
    router
      .get('/get/route/:prop', (req, res) => {
        res.end('/get/route/:prop called')
      })
      .post('/post/route/:prop', (req, res) => {
        res.end('/post/route/:prop called')
      })
      .put('/put/route/:prop', (req, res) => {
        res.end('/put/route/:prop called')
      })
      .patch('/patch/route/:prop', (req, res) => {
        res.end('/patch/route/:prop called')
      })
      .delete('/delete/route/:prop', (req, res) => {
        res.end('/delete/route/:prop called')
      })
      .route('/any/route/:prop', (req, res) => {
        res.end('/any/route/:prop called')
      })
    expect(loggerInfoFn).toBeCalledTimes(6)
    expect(loggerInfoFn.mock.calls).toEqual(
      [
        [
          'Route registered',
          {
            method: 'GET',
            regexStr: '^/get/route/(?<prop>\\w+)$',
            route: '/get/route/:prop',
          },
        ],
        [
          'Route registered',
          {
            method: 'POST',
            regexStr: '^/post/route/(?<prop>\\w+)$',
            route: '/post/route/:prop',
          },
        ],
        [
          'Route registered',
          {
            method: 'PUT',
            regexStr: '^/put/route/(?<prop>\\w+)$',
            route: '/put/route/:prop',
          },
        ],
        [
          'Route registered',
          {
            method: 'PATCH',
            regexStr: '^/patch/route/(?<prop>\\w+)$',
            route: '/patch/route/:prop',
          },
        ],
        [
          'Route registered',
          {
            method: 'DELETE',
            regexStr: '^/delete/route/(?<prop>\\w+)$',
            route: '/delete/route/:prop',
          },
        ],
        [
          'Route registered',
          {
            method: '*',
            regexStr: '^/any/route/(?<prop>\\w+)$',
            route: '/any/route/:prop',
          },
        ],
      ],
    )
  })

  test('Should handle request properly and save request info', async () => {
    const { loggerInfoFn, runDefaultFn } = reloadMock()
    const router = new RouterModule.Router()
    router
      .get('/method/:param', (req, res) => {
        res.writeHead(200).end(JSON.stringify({ params: req.params, query: req.query }))
      })
      .post('/method/:param', (req, res) => {
        res.writeHead(500).end()
      })
    expect(loggerInfoFn).toBeCalledTimes(2)
    const resMock = getResMock(jest, {
      req: {
        method: 'GET',
        url: '/method/123?a=abc&b=456',
        socket: {
          remoteAddress: '::ffff:201.26.160.146',
        },
        headers: { 'user-agent': 'testingHelpers/1.0.0' },
      },
    })
    router.handle(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(200)
    expect(resMock.body).toBe(JSON.stringify({
      params: {
        param: '123',
      },
      query: {
        a: 'abc',
        b: '456',
      },
    }))
    jest.advanceTimersByTime(5)
    resMock.res.emit('finish')
    await resMock.finishPromise
    expect(runDefaultFn).toBeCalled()
    expect(runDefaultFn.mock.calls).toEqual([
      [
        'insert into httpRequests (timestamp, method, path, timeElapsed, remoteIp, remoteHostname, statusCode, userAgent, body, headers) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          '1994-04-03T15:00:00.005Z',
          'GET',
          '/method/123',
          5000,
          '201.26.160.146',
          '201-26-160-146.dial-up.telesp.net.br',
          200,
          'testingHelpers/1.0.0',
          null,
          JSON.stringify({ 'user-agent': 'testingHelpers/1.0.0' }),
        ],
      ],
    ])
  })

  test('Should survive a proto poisoning attempt', async () => {
    const { loggerInfoFn } = reloadMock()
    const router = new RouterModule.Router()
    router
      .get('/method', (req, res) => {
        res.writeHead(200).end(JSON.stringify({ query: req.query }))
      })
    expect(loggerInfoFn).toBeCalledTimes(1)
    const resMock = getResMock(jest, {
      req: {
        url: '/method?a=abc&b=456&proto[toString]=true&toString=false&nested[deeper]=ashoash',
      },
    })
    router.handle(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(200)
    expect(JSON.parse(resMock.body)).toStrictEqual({
      query: {
        a: 'abc',
        b: '456',
        proto: {},
        nested: {
          deeper: 'ashoash',
        },
      },
    })
  })

  test('Should fall into the default handler when no match', async () => {
    const { runDefaultFn } = reloadMock()
    const router = new RouterModule.Router()
    const resMock = getResMock(jest, {
      req: {
        method: 'GET',
        url: '/',
        socket: {
          remoteAddress: '::ffff:201.26.160.146',
        },
        headers: { 'user-agent': 'testingHelpers/1.0.0' },
      },
    })
    router.handle(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(404)
    jest.advanceTimersByTime(5)
    resMock.res.emit('finish')
    await resMock.finishPromise
    await resMock.endPromise
    expect(resMock.body).toBe('')
    expect(runDefaultFn).toBeCalled()
    expect(runDefaultFn.mock.calls).toEqual([
      [
        'insert into httpRequests (timestamp, method, path, timeElapsed, remoteIp, remoteHostname, statusCode, userAgent, body, headers) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          '1994-04-03T15:00:00.005Z',
          'GET',
          '/',
          5000,
          '201.26.160.146',
          '201-26-160-146.dial-up.telesp.net.br',
          404,
          'testingHelpers/1.0.0',
          null,
          JSON.stringify({ 'user-agent': 'testingHelpers/1.0.0' }),
        ],
      ],
    ])
  })

  test('Should not insert request from localhost', async () => {
    const { runDefaultFn } = reloadMock()
    const router = new RouterModule.Router()
    const resMock = getResMock(jest, {
      req: {
        method: 'GET',
        url: '/',
        socket: {
          remoteAddress: '127.0.0.1',
        },
        headers: { 'user-agent': 'testingHelpers/1.0.0' },
      },
    })
    router.handle(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(404)
    jest.advanceTimersByTime(5)
    resMock.res.emit('finish')
    await resMock.finishPromise
    await resMock.endPromise
    expect(resMock.body).toBe('')
    expect(runDefaultFn).not.toBeCalled()
  })
})
