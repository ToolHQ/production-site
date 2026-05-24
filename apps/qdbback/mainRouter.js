import { Router } from './router.js'
import { debugHandler, indexHandler } from './handlers.js'
import { handleFileResponse, parseBody } from './utils.js'
import { cacheConstants, pkiCertFileName, mimeTypes } from './constants.js'
import { acceptLanguageHandler } from './handlerAcceptLanguage.js'
import { log } from './logger.js'
const cachePolicyImg = {
  time: cacheConstants.time.week,
  policy: cacheConstants.policies.public
}

const sensitiveDataCachePolicy = {
  time: cacheConstants.time.twoMinutes,
  policy: cacheConstants.policies.noStore
}

const noCachePolicy = {
  time: cacheConstants.time.year,
  policy: cacheConstants.policies.noCache
}

export const getRouter = () => {
  const router = new Router((_, res) => res
    .writeHead(404, { 'Content-type': mimeTypes.html })
    .end('<html>The resource you are looking are not available</html>')
  )

  router
    .get('/', indexHandler)
    .get('/index.html', indexHandler)
    .get(`/.well-known/pki-validation/${pkiCertFileName}`, handleFileResponse({ relativePath: `./assets/${pkiCertFileName}`, cache: noCachePolicy }))
    .get('/mydevtools/benchdata/db.csv', handleFileResponse({ relativePath: '../benchdata/db.csv', cache: sensitiveDataCachePolicy }))
    .post('/internal/csp-reports', async (req, res) => {
      try {
        const cspReport = await parseBody(req)
        log('cspReport INFO', cspReport)
        res.writeHead(200)
      } catch (err) {
        log('cspReport ERROR', { cause: err.message, stack: err.stack, body: req.body }, 'error')
        res.writeHead(500)
      }
      res.end()
    })
    .get('/favicon.ico', handleFileResponse({ relativePath: './assets/favicon-16x16.ico', cache: cachePolicyImg }))
    .get('/pudim.png', handleFileResponse({ relativePath: './assets/pudim.webp', cache: cachePolicyImg }))
    .get('/accept-languages', acceptLanguageHandler)
    .route('/debugme', debugHandler)
  return router
}
