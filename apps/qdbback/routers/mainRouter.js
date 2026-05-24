import { Router } from '../router.js'
import { debugHandler } from '../handlers/debugHandler.js'
import { handleFileResponse } from '../handlers/streamFileHandler.js'
import { cacheConstants, pkiCertFileName, mimeTypes } from '../constants.js'
import { acceptLanguageHandler } from '../handlers/acceptLanguage.js'
import { indexHandler } from '../handlers/indexHandler.js'
import { cspReportsHandler } from '../handlers/cspReportsHandler.js'
import { internalThreatSummaryHandler } from '../handlers/internalThreatSummaryHandler.js'

const cachePolicyImg = {
  time: cacheConstants.time.week,
  policy: cacheConstants.policies.public,
}

const sensitiveDataCachePolicy = {
  time: cacheConstants.time.twoMinutes,
  policy: cacheConstants.policies.noStore,
}

const noCachePolicy = {
  time: cacheConstants.time.year,
  policy: cacheConstants.policies.noCache,
}

export const getRouter = () => {
  const router = new Router((_, res) => res
    .writeHead(404, { 'Content-Type': mimeTypes.html })
    .end('<html>The resource you are looking are not available</html>'))

  router
    .get('/', indexHandler)
    .get('/index.html', indexHandler)
    .get(`/.well-known/pki-validation/${pkiCertFileName}`, handleFileResponse({ relativePath: `./assets/${pkiCertFileName}`, cache: noCachePolicy }))
    .get('/mydevtools/benchdata/db.csv', handleFileResponse({ relativePath: '../benchdata/db.csv', cache: sensitiveDataCachePolicy }))
    .post('/internal/csp-reports', cspReportsHandler)
    .get('/internal/threats-summary', internalThreatSummaryHandler)
    .get('/favicon.ico', handleFileResponse({ relativePath: './assets/favicon-16x16.ico', cache: cachePolicyImg }))
    .get('/pudim.png', handleFileResponse({ relativePath: './assets/pudim.webp', cache: cachePolicyImg }))
    .get('/accept-languages', acceptLanguageHandler)
    .route('/debugme', debugHandler)
  return router
}
