import { lookupService } from 'dns'

/**
 * Returns hostname by ip doing reverse lookup
 * @param {String} ip
 * @param {Number} port
 * @returns {Promise<String>}
 */
const lookupServiceAsync = (ip, port) => new Promise((resolve) => lookupService(ip, port,
  (err, hostname) => (err ? resolve(null) : resolve(hostname))))

const lookupResults = new Map()

export const getLookupResults = () => lookupResults

/**
 * @param {String} ip
 * @param {Number} port
 * @returns {Promise<String>}
 */
export const lookupServiceWithCache = async (ip, port) => {
  if (lookupResults.has(ip)) {
    return lookupResults.get(ip)
  }
  const hostname = await lookupServiceAsync(ip, port)
  lookupResults.set(ip, hostname)
  setTimeout(() => lookupResults.delete(ip), 60000)
  return hostname
}
