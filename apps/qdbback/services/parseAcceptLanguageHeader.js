/**
 * Parse accept-language header (eg.: 'en-US,en;q=0.9,pt-BR;q=0.8,pt;q=0.7')
 * @param {String} acceptLanguageHeaderStr
 * @returns {{ locale: String, weight: Number }[]}
 */
export const parseAcceptLanguageHeader = (acceptLanguageHeaderStr) => acceptLanguageHeaderStr
  .split(',')
  .reduce((pv, cv) => {
    const [rawLocale, rawWeight = 'q=1.0'] = cv.split(';')
    const locale = rawLocale.trim()
    const weight = Number(rawWeight.split('=')[1])
    if (pv.every((lang) => lang.locale !== locale)) {
      pv.push({
        locale,
        weight,
      })
    }
    return pv
  }, [])
  .sort((a, b) => {
    if (a.weight > b.weight) {
      return -1
    }
    if (a.weight < b.weight) {
      return 1
    }
    return 0
  })
