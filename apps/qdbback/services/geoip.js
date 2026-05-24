import geoip from 'geoip-lite'

const PRIVATE_RANGES = [
  /^127\./,
  /^10\./,
  /^192\.168\./,
  /^172\.(1[6-9]|2\d|3[01])\./,
  /^::1$/,
  /^fc/i,
  /^fd/i,
]

export const isPrivateIp = (ip) => {
  if (!ip) return true
  return PRIVATE_RANGES.some((pattern) => pattern.test(ip))
}

/**
 * @param {string | undefined} ip
 * @returns {string | null} ISO 3166-1 alpha-2 country code
 */
export const lookupCountry = (ip) => {
  if (isPrivateIp(ip)) return null
  const hit = geoip.lookup(ip)
  return hit?.country || null
}
