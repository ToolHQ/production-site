/**
 * This is an experiment to determine if JSON.stringify can be really slower.
 */

/**
 * Generates key-pair structure for JSON response
 * @param {String} key
 * @param {String} strValue
 * @param {Boolean} isObjStr
 */
export const stringifyKeyPair = (key, strValue, isObjStr = false) => {
  if (strValue === undefined) {
    return ''
  }
  if (strValue === null) {
    return `"${key}":null`
  }
  if (typeof strValue === 'string' && !isObjStr) {
    return `"${key}":"${strValue.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`
  }
  return `"${key}":${strValue}`
}

/**
 * Creates partial json for plain js object
 * @param {Object.<string, undefined|null|string|boolean|number>} obj
 * @returns
 */
export const stringifyPlainMap = (obj) => {
  const keyPairs = Object.entries(obj).reduce((pv, [headerKey, headerValue]) => {
    const keyPair = stringifyKeyPair(headerKey, headerValue)
    if (keyPair) {
      pv.push(keyPair)
    }
    return pv
  }, [])
  return `{${keyPairs.join(',')}}`
}

/**
 * @param {String[]} keyPairs
 */
export const finalizeToJSON = (keyPairs) => `{${keyPairs.filter(Boolean).join(',')}}`
