import {
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

  const reloadMock = () => {
    loggerInfoFn.mockReset()
    loggerErrorFn.mockReset()
    return {
      loggerInfoFn,
      loggerErrorFn,
    }
  }
  return {
    reloadMock,
  }
}

const { reloadMock } = initMock()

/** @type {import('./cspReportsHandler.js').cspReportsHandler} */
let cspReportsHandler

describe('handlers/cspReportsHandler.js', () => {
  beforeAll(async () => {
    cspReportsHandler = (await import('./cspReportsHandler.js')).cspReportsHandler
  })

  test('Should resolve with parsed json when csp-report payload', async () => {
    const req = new Req()
    req.setHeader('content-type', 'application/csp-report')
    const resMock = getResMock(jest, { req })
    const { loggerInfoFn, loggerErrorFn } = reloadMock()
    const promise = cspReportsHandler(resMock.req, resMock.res)
    const cspReport = {
      'csp-report': {
        'document-uri': 'https://example.com/signup.html',
        referrer: '',
        'blocked-uri': 'https://example.com/css/style.css',
        'violated-directive': 'style-src cdn.example.com',
        'original-policy': "default-src 'none'; style-src cdn.example.com; report-uri /internal/csp-reports",
        disposition: 'report',
      },
    }
    req.emit('data', Buffer.from(JSON.stringify(cspReport)))
    req.emit('end')
    await promise
    expect(resMock.statusCode).toBe(200)
    expect(loggerErrorFn).not.toBeCalled()
    expect(loggerInfoFn).toBeCalledWith('cspReport INFO', cspReport)
    expect(resMock.res.end).toBeCalled()
  })

  test('Should log error properly and return 500 when invalid payload', async () => {
    const req = new Req()
    req.setHeader('content-type', 'application/csp-report')
    const resMock = getResMock(jest, { req })
    const { loggerInfoFn, loggerErrorFn } = reloadMock()
    const promise = cspReportsHandler(resMock.req, resMock.res)
    req.emit('data', Buffer.from('<html>Not a JSON</html>'))
    req.emit('end')
    await promise
    expect(resMock.statusCode).toBe(500)
    expect(loggerInfoFn).not.toBeCalled()
    expect(loggerErrorFn).toBeCalledTimes(1)
    expect(loggerErrorFn.mock.calls[0][0]).toBe('cspReport ERROR')
    expect(resMock.res.end).toBeCalled()
  })
})
