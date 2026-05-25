import {
  beforeAll,
  beforeEach,
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

/** @type {typeof import('./prometheusMetricsHandler.js').prometheusMetricsHandler} */
let prometheusMetricsHandler

/** @type {typeof import('../services/qdbbackMetrics.js').resetPrometheusMetricsCache} */
let resetPrometheusMetricsCache

describe('handlers/prometheusMetricsHandler.js', () => {
  beforeAll(async () => {
    prometheusMetricsHandler = (await import('./prometheusMetricsHandler.js')).prometheusMetricsHandler
    resetPrometheusMetricsCache = (await import('../services/qdbbackMetrics.js')).resetPrometheusMetricsCache
  })

  beforeEach(() => {
    resetPrometheusMetricsCache()
  })

  test('returns 403 for non-allowlisted IP', async () => {
    reloadMock()
    const resMock = getResMock(jest, {
      req: {
        socket: { remoteAddress: '1.2.3.4' },
      },
    })
    buildReq(resMock.req)
    await prometheusMetricsHandler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(403)
    expect(resMock.body).toBe('forbidden\n')
  })

  test('returns prometheus text for allowlisted OCI IP', async () => {
    const { allDefaultFn } = reloadMock()
    allDefaultFn
      .mockResolvedValueOnce([{ total: 100 }])
      .mockResolvedValueOnce([{ last24h: 12 }])
      .mockResolvedValueOnce([{ classified: 40 }])

    const resMock = getResMock(jest, {
      req: {
        socket: { remoteAddress: '150.136.34.254' },
      },
    })
    buildReq(resMock.req)
    await prometheusMetricsHandler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(200)
    expect(resMock.headers['Content-Type']).toContain('text/plain')
    expect(resMock.body).toContain('qdbback_http_requests_total 100')
    expect(resMock.body).toContain('qdbback_http_requests_last24h 12')
    expect(resMock.body).toContain('qdbback_http_requests_classified_total 40')
    expect(resMock.body).toContain('qdbback_http_requests_unclassified_total 60')
    expect(resMock.body).toContain('qdbback_process_uptime_seconds')
    expect(resMock.body).toContain('qdbback_build_info{version=')
  })
})
