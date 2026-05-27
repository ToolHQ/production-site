import crypto from 'crypto'

import { isProduction } from '../config.js'

/** @deprecated — mantido só para dev local sem env */
const LEGACY_COOKIE = '215eaf6a-74c4-42cf-8417-b8f395bfeea6'
const LEGACY_LOGIN_KEY = 'palmeirasnaotemmundial'

export const getMonitorSecret = () => process.env.QDBBACK_MONITOR_SECRET || null

export const getMonitorLoginKey = () => (
  process.env.QDBBACK_MONITOR_LOGIN_KEY
  || getMonitorSecret()
  || (!isProduction ? LEGACY_LOGIN_KEY : null)
)

export const getMonitorCookieToken = () => {
  const secret = getMonitorSecret()
  if (!secret) {
    return isProduction ? null : LEGACY_COOKIE
  }
  const hash = crypto.createHash('sha256').update(`qdbback-monitor:${secret}`).digest('hex')
  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-${hash.slice(12, 16)}-${hash.slice(16, 20)}-${hash.slice(20, 32)}`
}

export const isMonitorAuthenticated = (req) => {
  const token = getMonitorCookieToken()
  if (!token) return false
  return (req?.headers?.cookie || '').includes(`monitor-key=${token}`)
}

/**
 * @returns {boolean} true quando o request deve ser bloqueado (404)
 */
export const monitorAuthMiddleware = (req, res) => {
  const loginKey = getMonitorLoginKey()
  if (loginKey && req?.query?.key === loginKey) {
    const token = getMonitorCookieToken()
    if (token) {
      res.setHeader('Set-Cookie', `monitor-key=${token}; Max-Age=28800; Path=/; HttpOnly; Secure`)
      return false
    }
  }
  return !isMonitorAuthenticated(req)
}
