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
  const allDefaultFn = jest.fn(async () => null)

  jest.mockModule('../sqlite3.js', () => ({
    allDefault: allDefaultFn,
  }))

  const reloadMock = () => {
    allDefaultFn.mockReset()
    return { allDefaultFn }
  }

  return { reloadMock }
}

const { reloadMock } = initMock()

/** @type {typeof import('./internalThreatSummaryHandler.js').internalThreatSummaryHandler} */
let internalThreatSummaryHandler

describe('handlers/internalThreatSummaryHandler.js', () => {
  beforeAll(async () => {
    internalThreatSummaryHandler = (await import('./internalThreatSummaryHandler.js')).internalThreatSummaryHandler
  })

  test('returns 403 for non-allowlisted IP', async () => {
    reloadMock()
    const resMock = getResMock(jest, {
      req: {
        socket: { remoteAddress: '1.2.3.4' },
      },
    })
    buildReq(resMock.req)
    await internalThreatSummaryHandler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(403)
    expect(JSON.parse(resMock.body)).toEqual({ error: 'forbidden' })
  })

  test('returns threat summary for allowlisted OCI IP', async () => {
    const { allDefaultFn } = reloadMock()
    allDefaultFn
      .mockResolvedValueOnce([{ total: 100 }])
      .mockResolvedValueOnce([{ tag: 'env-leak', count: 5 }])
      .mockResolvedValueOnce([{ last24h: 12 }])
      .mockResolvedValueOnce([{ classified: 40 }])

    const resMock = getResMock(jest, {
      req: {
        socket: { remoteAddress: '150.136.34.254' },
      },
    })
    buildReq(resMock.req)
    await internalThreatSummaryHandler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(200)
    expect(JSON.parse(resMock.body)).toEqual({
      total: 100,
      last24h: 12,
      classified: 40,
      unclassified: 60,
      topTags: [{ tag: 'env-leak', count: 5 }],
    })
  })
})
