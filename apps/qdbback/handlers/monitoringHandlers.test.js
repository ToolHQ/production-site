import { Readable } from 'stream'

import {
  beforeAll,
  describe,
  expect,
  jest,
  test,
} from '@jest/globals'

import { getResMock } from '../testingHelpers.js'
import { buildReq } from '../router.js'

const initMock = () => {
  const loggerInfoFn = jest.fn()
  const loggerErrorFn = jest.fn()
  const allDefaultFn = jest.fn(async () => null)
  const getStreamFromSQLFn = jest.fn(() => Readable.from(JSON.stringify({})))
  const getStreamFromAnySQLFn = jest.fn()

  jest.mockModule('../logger.js', () => ({
    logger: {
      info: loggerInfoFn,
      error: loggerErrorFn,
    },
  }))

  jest.mockModule('../sqlite3.js', () => ({
    getStreamFromSQL: getStreamFromSQLFn,
    allDefault: allDefaultFn,
    getStreamFromAnySQL: getStreamFromAnySQLFn,
  }))

  const reloadMock = ({
    allDefaultResult,
    streamSQLResult = {},
  }) => {
    loggerInfoFn.mockReset()
    loggerErrorFn.mockReset()
    allDefaultFn.mockReset().mockImplementation(async () => allDefaultResult)
    getStreamFromSQLFn.mockReset().mockImplementation(() => Readable.from(JSON.stringify(streamSQLResult)))
    getStreamFromAnySQLFn.mockReset().mockImplementation(() => Readable.from(JSON.stringify(streamSQLResult)))
    return {
      getStreamFromSQLFn,
      allDefaultFn,
      getStreamFromAnySQLFn,
      loggerInfoFn,
      loggerErrorFn,
    }
  }
  return {
    reloadMock,
  }
}

const { reloadMock } = initMock()

/** @type {import('./monitoringHandlers')}.js */
let monitoringHandlers

describe('handlers/monitoringHandlers.js', () => {
  beforeAll(async () => {
    monitoringHandlers = await import('./monitoringHandlers')
  })

  describe('#queryHttpRequestsHandler', () => {
    test('Should output 200 result making proper query', async () => {
      const { loggerErrorFn, getStreamFromSQLFn } = reloadMock({
        allDefaultResult: [{ total: 42 }],
        streamSQLResult: {
          total: 42,
          rows: [
            {
              id: 42,
              method: 'GET',
              path: '/lorem',
            },
            {
              id: 41,
              method: 'POST',
              path: '/ipsum',
            },
            {
              id: 40,
              method: 'GET',
              path: '/mussum',
            }],
        },
      })
      const resMock = getResMock(jest, {
        req: {
          headers: {
            'accept-encoding': 'identity',
          },
          url: '/api/monitor/requests?limit=3&part=id,method,path&sort_by=desc(id),asc(method)',
        },
      })
      buildReq(resMock.req)
      await monitoringHandlers.queryHttpRequestsHandler(resMock.req, resMock.res)
      expect(resMock.statusCode).toBe(200)
      expect(resMock.headers).toStrictEqual({
        'Cache-Control': 'no-store',
        'Content-Encoding': 'identity',
        'Content-Type': 'application/json',
      })
      await resMock.endPromise
      resMock.res.emit('finish')
      await resMock.finishPromise
      expect(loggerErrorFn).not.toBeCalled()
      expect(getStreamFromSQLFn).toBeCalledWith(`
SELECT id, method, path
FROM httpRequests
ORDER BY id DESC, method ASC
LIMIT $limit
OFFSET $offset`, { $limit: 3, $offset: 0 }, 42)
      expect(resMock.body).toEqual(JSON.stringify({
        total: 42,
        rows: [
          {
            id: 42,
            method: 'GET',
            path: '/lorem',
          },
          {
            id: 41,
            method: 'POST',
            path: '/ipsum',
          },
          {
            id: 40,
            method: 'GET',
            path: '/mussum',
          }],
      }))
    })

    test('Should output 200 result making proper query with default values', async () => {
      const { loggerErrorFn, getStreamFromSQLFn } = reloadMock({
        allDefaultResult: [{ total: 100 }],
      })
      const resMock = getResMock(jest, {
        req: {
          headers: {
            'accept-encoding': 'identity',
          },
          url: '/api/monitor/requests',
        },
      })
      buildReq(resMock.req)
      await monitoringHandlers.queryHttpRequestsHandler(resMock.req, resMock.res)
      await resMock.endPromise
      resMock.res.emit('finish')
      await resMock.finishPromise
      expect(loggerErrorFn).not.toBeCalled()
      expect(resMock.statusCode).toBe(200)
      expect(getStreamFromSQLFn).toBeCalledWith(`
SELECT id, timestamp, method, path, timeElapsed, remoteHostname, statusCode, country, classification
FROM httpRequests
ORDER BY id DESC
LIMIT $limit
OFFSET $offset`, { $limit: 25, $offset: 0 }, 100)
    })
  })

  describe('#queryLogsHandler', () => {
    test('Should output 200 result making proper query', async () => {
      const { loggerErrorFn, getStreamFromSQLFn } = reloadMock({
        allDefaultResult: [{ total: 4 }],
        streamSQLResult: {
          total: 4,
          rows: [
            {
              id: 4,
              severity: 'error',
            },
            {
              id: 3,
              severity: 'info',
            },
          ],
        },
      })
      const resMock = getResMock(jest, {
        req: {
          headers: {
            'accept-encoding': 'identity',
          },
          url: '/api/monitor/logs?limit=2&part=id,severity&sort_by=desc(id),asc(severity)',
        },
      })
      buildReq(resMock.req)
      await monitoringHandlers.queryLogsHandler(resMock.req, resMock.res)
      expect(resMock.statusCode).toBe(200)
      expect(resMock.headers).toStrictEqual({
        'Cache-Control': 'no-store',
        'Content-Encoding': 'identity',
        'Content-Type': 'application/json',
      })
      await resMock.endPromise
      resMock.res.emit('finish')
      await resMock.finishPromise
      expect(loggerErrorFn).not.toBeCalled()
      expect(getStreamFromSQLFn).toBeCalledWith(`
SELECT id, severity
FROM applicationLogs
ORDER BY id DESC, severity ASC
LIMIT $limit
OFFSET $offset`, { $limit: 2, $offset: 0 }, 4)
      expect(resMock.body).toEqual(JSON.stringify({
        total: 4,
        rows: [
          {
            id: 4,
            severity: 'error',
          },
          {
            id: 3,
            severity: 'info',
          },
        ],
      }))
    })

    test('Should output 200 result making proper query with default values', async () => {
      const { loggerErrorFn, getStreamFromSQLFn } = reloadMock({
        allDefaultResult: [{ total: 100 }],
      })
      const resMock = getResMock(jest, {
        req: {
          headers: {
            'accept-encoding': 'identity',
          },
          url: '/api/monitor/logs',
        },
      })
      buildReq(resMock.req)
      await monitoringHandlers.queryLogsHandler(resMock.req, resMock.res)
      await resMock.endPromise
      resMock.res.emit('finish')
      await resMock.finishPromise
      expect(loggerErrorFn).not.toBeCalled()
      expect(resMock.statusCode).toBe(200)
      expect(getStreamFromSQLFn).toBeCalledWith(`
SELECT id, timestamp, severity, event, log
FROM applicationLogs
ORDER BY id DESC
LIMIT $limit
OFFSET $offset`, { $limit: 25, $offset: 0 }, 100)
    })
  })

  describe('#queryAnySQLHandler', () => {
    test('Should output 200 result making proper query provided', async () => {
      const { loggerErrorFn, getStreamFromAnySQLFn } = reloadMock({
        streamSQLResult: {
          total: 4,
          rows: [
            {
              id: 4,
              name: 'Daniel',
            },
            {
              id: 3,
              name: 'Norio',
            },
          ],
        },
      })
      const resMock = getResMock(jest, {
        req: {
          headers: {
            'accept-encoding': 'identity',
          },
        },
      })
      buildReq(resMock.req)
      resMock.req.body = 'SELECT id, name FROM users'
      await monitoringHandlers.queryAnySQLHandler(resMock.req, resMock.res)
      expect(resMock.statusCode).toBe(200)
      expect(resMock.headers).toStrictEqual({
        'Cache-Control': 'no-store',
        'Content-Encoding': 'identity',
        'Content-Type': 'application/json',
      })
      await resMock.endPromise
      resMock.res.emit('finish')
      await resMock.finishPromise
      expect(loggerErrorFn).not.toBeCalled()
      expect(getStreamFromAnySQLFn).toBeCalledWith('SELECT id, name FROM users', {})
      expect(resMock.body).toEqual(JSON.stringify({
        total: 4,
        rows: [
          {
            id: 4,
            name: 'Daniel',
          },
          {
            id: 3,
            name: 'Norio',
          },
        ],
      }))
    })
  })
})
