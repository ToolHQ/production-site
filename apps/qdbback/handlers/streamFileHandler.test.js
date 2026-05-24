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

import { getResMock, Req } from '../testingHelpers.js'

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

/** @type {import('./streamFileHandler.js').handleFileResponse} */
let handleFileResponse

describe('handlers/streamFileHandler.js', () => {
  beforeAll(async () => {
    handleFileResponse = (await import('./streamFileHandler.js')).handleFileResponse
    jest.useFakeTimers()
    jest.setSystemTime(765403200000)
  })

  afterAll(() => {
    jest.useRealTimers()
  })

  test('Should end without payload when HEAD method and return proper control headers', async () => {
    const req = new Req()
    req.method = 'HEAD'
    const resMock = getResMock(jest, { req })
    const { loggerErrorFn, fileLastModifiedFn, createReadStreamFn } = reloadMock({})
    const handler = handleFileResponse({
      relativePath: 'test1.css',
    })
    await handler(resMock.req, resMock.res)
    expect(fileLastModifiedFn).toBeCalledTimes(1)
    expect(fileLastModifiedFn).toBeCalledWith('test1.css')
    expect(loggerErrorFn).not.toBeCalled()
    expect(createReadStreamFn).not.toBeCalled()

    expect(resMock.statusCode).toBe(200)
    expect(resMock.headers).toStrictEqual({
      'Cache-Control': 'no-cache',
      'Content-Type': 'text/css',
      ETag: '40bd001563085fc35165329ea1ff5c5ecbdbbeef',
      Expires: 'Sun, 03 Apr 1994 20:02:00 GMT',
      Vary: 'ETag',
    })
    expect(resMock.res.end).toBeCalled()
  })

  test('Should not fetch lastModified at 2o request for same file', async () => {
    const req = new Req()
    req.method = 'HEAD'
    const resMock = getResMock(jest, { req })
    const { fileLastModifiedFn } = reloadMock({})
    const handler = handleFileResponse({
      relativePath: 'test2.css',
    })
    await handler(resMock.req, resMock.res)
    expect(fileLastModifiedFn).toBeCalledTimes(1)
    expect(fileLastModifiedFn).toBeCalledWith('test2.css')
    expect(resMock.statusCode).toBe(200)
    expect(resMock.res.end).toBeCalledTimes(1)

    await handler(resMock.req, resMock.res)
    expect(fileLastModifiedFn).toBeCalledTimes(1)
    expect(resMock.statusCode).toBe(200)
    expect(resMock.res.end).toBeCalledTimes(2)
  })

  test('Should return 304 when ETag matches', async () => {
    const req = new Req()
    req.setHeader('if-none-match', '40bd001563085fc35165329ea1ff5c5ecbdbbeef')
    const resMock = getResMock(jest, { req })
    reloadMock({})
    const handler = handleFileResponse({
      relativePath: 'somehtml.html',
    })
    await handler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(304)
    expect(resMock.headers).toStrictEqual({
      'Cache-Control': 'no-cache',
      'Content-Type': 'text/html; charset=utf-8',
      ETag: '40bd001563085fc35165329ea1ff5c5ecbdbbeef',
      Expires: 'Sun, 03 Apr 1994 20:02:00 GMT',
      Vary: 'ETag',
    })
    expect(resMock.res.end).toBeCalledTimes(1)
  })

  test('Should return 200 with content streamed without enconding', async () => {
    const req = new Req()
    const resMock = getResMock(jest, { req })
    reloadMock({
      fileData: 'Some plain text data',
    })
    const handler = handleFileResponse({
      relativePath: 'somehtml.html',
      encoding: false,
    })
    await handler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(200)
    expect(resMock.headers).toStrictEqual({
      'Cache-Control': 'no-cache',
      'Content-Type': 'text/html; charset=utf-8',
      ETag: '40bd001563085fc35165329ea1ff5c5ecbdbbeef',
      Expires: 'Sun, 03 Apr 1994 20:02:00 GMT',
      Vary: 'ETag',
    })
    await resMock.endPromise
    expect(resMock.body).toBe('Some plain text data')
  })

  test('Should return 200 with content streamed without enconding when accept-encoding=identity', async () => {
    const req = new Req()
    req.setHeader('accept-encoding', 'identity')
    const resMock = getResMock(jest, { req })
    reloadMock({
      fileData: 'Some plain text data',
    })
    const handler = handleFileResponse({
      relativePath: 'somehtml.html',
      encoding: true,
    })
    await handler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(200)
    expect(resMock.headers).toStrictEqual({
      'Cache-Control': 'no-cache',
      'Content-Encoding': 'identity',
      'Content-Type': 'text/html; charset=utf-8',
      ETag: '40bd001563085fc35165329ea1ff5c5ecbdbbeef',
      Expires: 'Sun, 03 Apr 1994 20:02:00 GMT',
      Vary: 'ETag',
    })
    await resMock.endPromise
    expect(resMock.body).toBe('Some plain text data')
  })

  test('Should return 406 when accept-encoding demands unknown enconding', async () => {
    const req = new Req()
    req.setHeader('accept-encoding', 'bzip2,   *;q=0')
    const resMock = getResMock(jest, { req })
    reloadMock({})
    const handler = handleFileResponse({
      relativePath: 'somehtml.html',
      encoding: true,
    })
    await handler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(406)
    expect(resMock.headers).toStrictEqual({
      'Cache-Control': 'no-cache',
      'Content-Type': 'application/json',
      ETag: '40bd001563085fc35165329ea1ff5c5ecbdbbeef',
      Expires: 'Sun, 03 Apr 1994 20:02:00 GMT',
      Vary: 'ETag',
    })
    await resMock.endPromise
    expect(resMock.body).toBe('{"error":"Encoding Not Supported"}')
  })

  test('Should return 200 with content streamed and compressed when accept-encoding="gzip, deflate, br"', async () => {
    const req = new Req()
    req.setHeader('accept-encoding', 'gzip, deflate, br')
    const resMock = getResMock(jest, { req })
    reloadMock({
      fileData: 'Some plain text data',
    })
    const handler = handleFileResponse({
      relativePath: 'somehtml.html',
      encoding: true,
    })
    await handler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(200)
    expect(resMock.headers).toStrictEqual({
      'Cache-Control': 'no-cache',
      'Content-Encoding': 'gzip',
      'Content-Type': 'text/html; charset=utf-8',
      ETag: '40bd001563085fc35165329ea1ff5c5ecbdbbeef',
      Expires: 'Sun, 03 Apr 1994 20:02:00 GMT',
      Vary: 'ETag',
    })
    await resMock.endPromise
    expect(resMock.body).toBe(zlib.gzipSync('Some plain text data').toString())
  })
})
