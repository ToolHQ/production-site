import { Readable } from 'stream'
import zlib from 'zlib'

import {
  afterAll,
  beforeAll,
  describe,
  expect,
  jest,
  test,
} from '@jest/globals'

import { getResMock } from '../testingHelpers.js'

const FIXED_SYSTEM_TIME = '1994-04-03T15:00:00.000Z'

const initMock = () => {
  const loggerInfoFn = jest.fn()
  const loggerErrorFn = jest.fn()

  jest.mockModule('../logger.js', () => ({
    logger: {
      info: loggerInfoFn,
      error: loggerErrorFn,
    },
  }))

  const createReadStreamFn = jest.fn(() => Readable.from('Hello World'))
  const fileLastModifiedFn = jest.fn(() => 123)
  jest.mockModule('../services/fs.js', () => ({
    createReadStream: createReadStreamFn,
    fileLastModified: fileLastModifiedFn,
  }))

  const reloadMock = ({
    fileData = 'Hello world',
    fileLastModified = 123,
  }) => {
    const readable = Readable.from(fileData)
    loggerInfoFn.mockReset()
    loggerErrorFn.mockReset()
    createReadStreamFn.mockReset().mockImplementation(() => readable)
    fileLastModifiedFn.mockReset().mockImplementation(() => fileLastModified)
    return {
      readable,
      loggerInfoFn,
      loggerErrorFn,
      createReadStreamFn,
      fileLastModifiedFn,
    }
  }
  return {
    reloadMock,
  }
}

const { reloadMock } = initMock()

/** @type {import('./streamEncodedHandler.js').getStreamHandler} */
let getStreamHandler

describe('handlers/streamEncodedHandler.js', () => {
  beforeAll(async () => {
    getStreamHandler = (await import('./streamEncodedHandler.js')).getStreamHandler
    jest.useFakeTimers()
    jest.setSystemTime(Date.parse(FIXED_SYSTEM_TIME))
  })

  afterAll(() => {
    jest.useRealTimers()
  })

  test('Should return 406 when accept-encoding demands unknown enconding', async () => {
    reloadMock({})
    const handler = getStreamHandler((req) => [req])
    const resMock = getResMock(jest, {
      req: {
        headers: {
          'accept-encoding': 'bzip2,   *;q=0',
        },
      },
    })
    await handler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(406)
    expect(resMock.headers).toStrictEqual({
      'Content-Type': 'application/json',
    })
    await resMock.endPromise
    expect(JSON.parse(resMock.body)).toStrictEqual({
      error: 'Encoding Not Supported',
    })
  })

  test('Should output 200 gziped response with the same input content when handler returns [req]', async () => {
    reloadMock({})
    const handler = getStreamHandler((req) => [req])
    const resMock = getResMock(jest, {
      req: {
        headers: {
          'accept-encoding': 'gzip',
        },
      },
    })
    await handler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(200)
    expect(resMock.headers).toStrictEqual({
      'Cache-Control': 'no-store',
      'Content-Encoding': 'gzip',
      'Content-Type': 'application/json',
    })
    resMock.req.emit('data', JSON.stringify({ test: '123' }))
    resMock.req.emit('end')
    await resMock.endPromise
    resMock.res.emit('finish')
    await resMock.finishPromise
    expect(resMock.body).toEqual(zlib.gzipSync(JSON.stringify({
      test: '123',
    })).toString())
  })

  test('Should output 200 gziped response with the same input content when handler returns req', async () => {
    reloadMock({})
    const handler = getStreamHandler((req) => req)
    const resMock = getResMock(jest, {
      req: {
        headers: {
          'accept-encoding': 'gzip',
        },
      },
    })

    await handler(resMock.req, resMock.res)
    resMock.req.emit('data', JSON.stringify({ test: '123' }))
    resMock.req.emit('end')
    await resMock.endPromise
    resMock.res.emit('finish')
    await resMock.finishPromise

    expect(resMock.statusCode).toBe(200)
    expect(resMock.headers).toStrictEqual({
      'Cache-Control': 'no-store',
      'Content-Encoding': 'gzip',
      'Content-Type': 'application/json',
    })
    expect(resMock.body).toEqual(zlib.gzipSync(JSON.stringify({
      test: '123',
    })).toString())
  })

  test('Should output 200 deflated response with the same input content when handler returns [req]', async () => {
    reloadMock({})
    const handler = getStreamHandler((req) => [req])
    const resMock = getResMock(jest, {
      req: {
        headers: {
          'accept-encoding': 'deflate',
        },
      },
    })
    await handler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(200)
    expect(resMock.headers).toStrictEqual({
      'Cache-Control': 'no-store',
      'Content-Encoding': 'deflate',
      'Content-Type': 'application/json',
    })
    resMock.req.emit('data', JSON.stringify({ test: '123' }))
    resMock.req.emit('end')
    await resMock.endPromise
    resMock.res.emit('finish')
    await resMock.finishPromise
    expect(resMock.body).toEqual(zlib.deflateSync(JSON.stringify({
      test: '123',
    })).toString())
  })

  test('Should output 200 brotli response with the same input content when handler returns [req]', async () => {
    reloadMock({})
    const handler = getStreamHandler((req) => [req])
    const resMock = getResMock(jest, {
      req: {
        headers: {
          'accept-encoding': 'br',
        },
      },
    })
    await handler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(200)
    expect(resMock.headers).toStrictEqual({
      'Cache-Control': 'no-store',
      'Content-Encoding': 'br',
      'Content-Type': 'application/json',
    })
    resMock.req.emit('data', JSON.stringify({ test: '123' }))
    resMock.req.emit('end')
    await resMock.endPromise
    resMock.res.emit('finish')
    await resMock.finishPromise
    expect(resMock.body).toEqual(zlib.brotliCompressSync(JSON.stringify({
      test: '123',
    })).toString())
  })

  test('Should return 500 with generic error when no Stream is provided and propagateErrors=false', async () => {
    const { loggerErrorFn } = reloadMock({})
    const handler = getStreamHandler((req) => ([{
      headers: req.headers,
    }]), false)
    const resMock = getResMock(jest, {
      req: {
        headers: {
          'accept-encoding': 'gzip',
        },
      },
    })
    resMock.req.path = 'some/path'
    await handler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(500)
    expect(resMock.headers).toStrictEqual({
      'Cache-Control': 'no-store',
      'Content-Encoding': 'identity',
      'Content-Type': 'application/json',
    })
    expect(loggerErrorFn).toBeCalledTimes(1)
    expect(loggerErrorFn.mock.calls[0][0]).toBe('some/path Handler ERROR')
    expect(loggerErrorFn.mock.calls[0][1]).toHaveProperty('message')
    expect(loggerErrorFn.mock.calls[0][1].message)
      .toContain('Received an instance of Object')
    expect(resMock.body).toEqual(JSON.stringify({
      message: 'Internal Server Error',
    }))
  })

  test('Should return 500 with generic error when no Stream is provided and propagateErrors=true', async () => {
    const { loggerErrorFn } = reloadMock({})
    const handler = getStreamHandler((req) => ([{
      headers: req.headers,
    }]), true)
    const resMock = getResMock(jest, {
      req: {
        headers: {
          'accept-encoding': 'gzip',
        },
      },
    })
    resMock.req.path = 'some/path/more/internal'
    await handler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(500)
    expect(resMock.headers).toStrictEqual({
      'Cache-Control': 'no-store',
      'Content-Encoding': 'identity',
      'Content-Type': 'application/json',
    })
    expect(loggerErrorFn).toBeCalledTimes(1)
    expect(loggerErrorFn.mock.calls[0][0]).toBe('some/path/more/internal Handler ERROR')
    expect(loggerErrorFn.mock.calls[0][1]).toHaveProperty('message')
    expect(loggerErrorFn.mock.calls[0][1].message)
      .toContain('Received an instance of Object')
    expect(resMock.body).toEqual(JSON.stringify({
      message: loggerErrorFn.mock.calls[0][1].message,
    }))
  })
})
