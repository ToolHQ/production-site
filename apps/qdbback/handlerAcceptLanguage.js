import { mimeTypes } from './constants.js'

/**
 * Utils for internacionalization
 */

/**
 * @type {import('./router').RequestListener}
 */
export const acceptLanguageHandler = (req, res) => {
  res.writeHead(200, {
    'Content-Type': mimeTypes.json
  })
  const acceptLanguage = req.headers['accept-language']
  const languages = acceptLanguage
    .split(',')
    .reduce((pv, cv) => {
      const [rawLocale, rawWeight = 'q=1.0'] = cv.split(';')
      const locale = rawLocale.trim()
      const weight = Number(rawWeight.split('=')[1])
      if (pv.every(lang => lang.locale !== locale)) {
        pv.push({
          locale,
          weight
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
  res.end(JSON.stringify({ languages }))
}
