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
  const fetchThreatTimeseriesFn = jest.fn(async () => ({
    requests24h: [{ timestamp: 1, value: 2 }],
    requests7d: [{ timestamp: 1, value: 20 }],
  }))

  jest.mockModule('../services/threatTimeseries.js', () => ({
    fetchThreatTimeseries: fetchThreatTimeseriesFn,
  }))

  return { fetchThreatTimeseriesFn }
}

const { fetchThreatTimeseriesFn } = initMock()

/** @type {typeof import('./internalThreatTimeseriesHandler.js').internalThreatTimeseriesHandler} */
let internalThreatTimeseriesHandler

describe('handlers/internalThreatTimeseriesHandler.js', () => {
  beforeAll(async () => {
    internalThreatTimeseriesHandler = (await import('./internalThreatTimeseriesHandler.js')).internalThreatTimeseriesHandler
  })

  test('returns 403 for non-allowlisted IP', async () => {
    fetchThreatTimeseriesFn.mockClear()
    const resMock = getResMock(jest, {
      req: { socket: { remoteAddress: '1.2.3.4' } },
    })
    buildReq(resMock.req)
    await internalThreatTimeseriesHandler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(403)
    expect(fetchThreatTimeseriesFn).not.toHaveBeenCalled()
  })

  test('returns timeseries for allowlisted OCI IP', async () => {
    fetchThreatTimeseriesFn.mockClear()
    const resMock = getResMock(jest, {
      req: { socket: { remoteAddress: '150.136.34.254' } },
    })
    buildReq(resMock.req)
    await internalThreatTimeseriesHandler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(200)
    expect(JSON.parse(resMock.body)).toEqual({
      requests24h: [{ timestamp: 1, value: 2 }],
      requests7d: [{ timestamp: 1, value: 20 }],
    })
  })
})
