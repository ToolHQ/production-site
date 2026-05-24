import {
  afterEach,
  describe,
  expect,
  test,
} from '@jest/globals'

import {
  getMonitorCookieToken,
  getMonitorLoginKey,
  isMonitorAuthenticated,
  monitorAuthMiddleware,
} from './monitorAuth.js'

describe('services/monitorAuth.js', () => {
  afterEach(() => {
    delete process.env.QDBBACK_MONITOR_SECRET
    delete process.env.QDBBACK_MONITOR_LOGIN_KEY
  })

  test('derives stable cookie token from secret', () => {
    process.env.QDBBACK_MONITOR_SECRET = 'test-secret-123'
    const a = getMonitorCookieToken()
    const b = getMonitorCookieToken()
    expect(a).toBe(b)
    expect(a).toMatch(/^[a-f0-9-]{36}$/)
  })

  test('authenticates via derived cookie', () => {
    process.env.QDBBACK_MONITOR_SECRET = 'test-secret-123'
    const token = getMonitorCookieToken()
    expect(isMonitorAuthenticated({ headers: { cookie: `monitor-key=${token}` } })).toBe(true)
    expect(isMonitorAuthenticated({ headers: { cookie: 'monitor-key=invalid' } })).toBe(false)
  })

  test('login query sets cookie and allows access', () => {
    process.env.QDBBACK_MONITOR_SECRET = 'login-secret'
    const res = { headers: {}, setHeader(k, v) { this.headers[k] = v } }
    const req = { query: { key: getMonitorLoginKey() }, headers: {} }
    expect(monitorAuthMiddleware(req, res)).toBe(false)
    expect(res.headers['Set-Cookie']).toContain(`monitor-key=${getMonitorCookieToken()}`)
  })
})
