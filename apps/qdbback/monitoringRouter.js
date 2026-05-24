import { Router } from './router.js'
import sqlite3 from './sqlite3.js'
import { handleFileResponse, parseBody } from './utils.js'
import { cacheConstants, mimeTypes } from './constants.js'
import { getValidator } from './validations.js'
import { log } from './logger.js'
import { acceptLanguageHandler } from './handlerAcceptLanguage.js'

const cache = {
  time: cacheConstants.time.week,
  policy: cacheConstants.policies.noCache
}

const getPatternSplittedByComma = fields => {
  const fieldsStr = fields.join('|')
  return `^(${fieldsStr})(,(${fieldsStr}))*$`
}
const getPatternSplittedByCommaSortBy = fields => {
  const fieldsStr = fields.map(f => `asc\\(${f}\\)`).concat(fields.map(f => `desc\\(${f}\\)`)).join('|')
  return `^(${fieldsStr})(,(${fieldsStr}))*$`
}

const httpRequestsQueryFields = ['id', 'timestamp', 'method', 'path', 'timeElapsed', 'remoteHostname', 'statusCode']
const logsQueryFields = ['id', 'timestamp', 'severity', 'event', 'log']

const defaultPartHttpRequestsQuery = httpRequestsQueryFields.join(',')
const defaultPartLogsQuery = logsQueryFields.join(',')

const validateReq = getValidator({
  type: 'object',
  properties: {
    query: {
      type: 'object',
      properties: {
        limit: {
          type: 'number'
        },
        offset: {
          type: 'number'
        },
        part: {
          type: 'string',
          pattern: getPatternSplittedByComma(httpRequestsQueryFields)
        },
        sort_by: {
          type: 'string',
          pattern: getPatternSplittedByCommaSortBy(httpRequestsQueryFields)
        }
      },
      additionalProperties: false
    }
  },
  additionalProperties: true
})

const validateReqLogs = getValidator({
  type: 'object',
  properties: {
    query: {
      type: 'object',
      properties: {
        limit: {
          type: 'number'
        },
        offset: {
          type: 'number'
        },
        part: {
          type: 'string',
          pattern: getPatternSplittedByComma(logsQueryFields)
        },
        sort_by: {
          type: 'string',
          pattern: getPatternSplittedByCommaSortBy(logsQueryFields)
        }
      },
      additionalProperties: false
    }
  },
  additionalProperties: true
})

const getSelectFieldsFromPart = part => [...new Set(part.split(','))].join(', ')
const getOrderByFieldsFromSortBy = sortBy => {
  const fields = [...new Set(sortBy.split(','))]
  return fields.map(field => field.startsWith('asc') ? field.slice(4, -1) + ' ASC' : field.slice(5, -1) + ' DESC').join(', ')
}

export const getRouter = () => {
  const router = new Router()
  router
    .get('/', (_, res) => {
      res.writeHead(301, {
        location: '/monitor'
      }).end()
    })
    .get('/noscript.html', handleFileResponse({ relativePath: './noscript.html', cache, encoding: true }))
    .get('/monitor/(index.html)?', (_, res) => {
      res.writeHead(301, {
        location: '/monitor'
      }).end()
    })
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
    .get('/monitor/(requests|logs|sql)', handleFileResponse({ relativePath: './dist/monitor/index.html', cache, encoding: true }))
    .get('/monitor', handleFileResponse({ relativePath: './dist/monitor/index.html', cache, encoding: true }))
    .get('/index.js', handleFileResponse({ relativePath: './dist/monitor/index.js', cache, encoding: true }))
    .get('/style.css', handleFileResponse({ relativePath: './dist/monitor/style.css', cache, encoding: true }))
    .get('/favicon.ico', handleFileResponse({ relativePath: './assets/favicon-16x16.ico', cache }))
    .get('/accept-languages', acceptLanguageHandler)

    .get('/api/monitor/requests', router.getStreamHandler(async (req, res) => {
      const validationErrors = validateReq(req)
      if (validationErrors) {
        res.writeHead(400, {
          'Content-type': mimeTypes.json
        })
        res.end(`{"message":"${validationErrors.message}","schemaPath":"${validationErrors.schemaPath}"}`)
        return
      }
      const { query: { limit = 25, offset = 0, part = defaultPartHttpRequestsQuery, sort_by: sortBy = 'desc(id)' } } = req
      const selectFields = getSelectFieldsFromPart(part)
      const orderByFields = getOrderByFieldsFromSortBy(sortBy)
      const sql = `
SELECT ${selectFields}
FROM httpRequests
WHERE remoteHostname <> 'bd3782df.virtua.com.br'
ORDER BY ${orderByFields}
LIMIT $limit
OFFSET $offset`
      const [{ total }] = await sqlite3.allDefault('SELECT COUNT(*) total FROM httpRequests WHERE remoteHostname <> \'bd3782df.virtua.com.br\'')
      const dbStream = await sqlite3.getStreamFromSQL(sql, { $limit: parseInt(limit), $offset: parseInt(offset) }, total)
      return [dbStream]
    }))
    .get('/api/monitor/logs', router.getStreamHandler(async (req, res) => {
      const validationErrors = validateReqLogs(req)
      if (validationErrors) {
        res.writeHead(400, {
          'Content-type': mimeTypes.json
        })
        res.end(`{"message":"${validationErrors.message}","schemaPath":"${validationErrors.schemaPath}"}`)
        return
      }
      const { query: { limit = 25, offset = 0, part = defaultPartLogsQuery, sort_by: sortBy = 'desc(id)' } } = req
      const selectFields = getSelectFieldsFromPart(part)
      const orderByFields = getOrderByFieldsFromSortBy(sortBy)
      const sql = `
SELECT ${selectFields}
FROM applicationLogs
ORDER BY ${orderByFields}
LIMIT $limit
OFFSET $offset`
      const [{ total }] = await sqlite3.allDefault('SELECT COUNT(*) total FROM applicationLogs')
      const dbStream = await sqlite3.getStreamFromSQL(sql, { $limit: parseInt(limit), $offset: parseInt(offset) }, total)
      return [dbStream]
    }))

    .post('/api/monitor/sql', router.getStreamHandler(async (req, res) => {
      const sql = await parseBody(req)
      if (!sql) {
        res.writeHead(400, {
          'Content-type': mimeTypes.json
        })
        res.end('{"message":"Input must not be empty"}')
        return
      }
      log('RAW SQL QUERY', { sql })
      const dbStream = await sqlite3.getStreamFromAnySQL(sql, {})
      return [dbStream]
    }, true))

  return router
}
