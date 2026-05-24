import { Router } from '../router.js'
import { cacheConstants } from '../constants.js'
import { acceptLanguageHandler } from '../handlers/acceptLanguage.js'
import { handleFileResponse } from '../handlers/streamFileHandler.js'
import { cspReportsHandler } from '../handlers/cspReportsHandler.js'
import { systemReportHandler } from '../handlers/systemReportHandler.js'
import { validateQueryHttpRequestsHandler, validateQueryLogsHandler, validateQueryAnySQLHandler } from '../handlers/monitoringSchemas.js'
import { queryHttpRequestsHandler, queryLogsHandler, queryAnySQLHandler } from '../handlers/monitoringHandlers.js'

const cache = {
  time: cacheConstants.time.week,
  policy: cacheConstants.policies.noCache,
}

/**
 * @typedef {Object} RequestListenerExtraProperties
 * @property {String} path
 * @property {{ [key: string]: string }} query
 * @property {{ [key: string]: string }} [params]
 * @property {String} remoteIp
 */

/**
 * @param {import('http').IncomingMessage & RequestListenerExtraProperties} req
 * @param {import('http').ServerResponse} res
 * @returns {Boolean}
 */
const securityValidateMiddleware = (req, res) => {
  const firstStep = req?.query?.key === 'palmeirasnaotemmundial'
  if (firstStep) {
    res.setHeader('Set-Cookie', 'monitor-key=215eaf6a-74c4-42cf-8417-b8f395bfeea6; Max-Age=120; Path=/; HttpOnly; Secure')
    return false
  }

  return !req?.headers?.cookie?.includes('monitor-key=215eaf6a-74c4-42cf-8417-b8f395bfeea6')
}

export const getRouter = (isProduction) => {
  const router = isProduction ? new Router(
    (_, res) => {
      res.writeHead(404)
      res.end()
    },
    securityValidateMiddleware,
  ) : new Router()
  router
    .get('/', (_, res) => {
      res.writeHead(301, {
        Location: '/monitor/requests',
      }).end()
    })
    .get('/noscript.html', handleFileResponse({ relativePath: './noscript.html', cache, encoding: true }))
    .get('/monitor/(index.html)?', (_, res) => {
      res.writeHead(301, {
        Location: '/monitor/requests',
      }).end()
    })
    .get('/monitor/(requests|logs|sql|status)', handleFileResponse({ relativePath: './dist/monitor/index.html', cache, encoding: true }))
    .post('/internal/csp-reports', cspReportsHandler)
    .get('/monitor', handleFileResponse({ relativePath: './dist/monitor/index.html', cache, encoding: true }))
    .get('/index.js', handleFileResponse({ relativePath: './dist/monitor/index.js', cache, encoding: true }))
    .get('/style.css', handleFileResponse({ relativePath: './dist/monitor/style.css', cache, encoding: true }))
    .get('/favicon.ico', handleFileResponse({ relativePath: './assets/favicon-16x16.ico', cache }))
    .get('/accept-languages', acceptLanguageHandler)
    .get('/api/monitor/requests', validateQueryHttpRequestsHandler, queryHttpRequestsHandler)
    .get('/api/monitor/logs', validateQueryLogsHandler, queryLogsHandler)
    .post('/api/monitor/sql', validateQueryAnySQLHandler, queryAnySQLHandler)
    .get('/api/monitor/status', systemReportHandler)

  return router
}
