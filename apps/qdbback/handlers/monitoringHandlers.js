import { logger } from '../logger.js'
import { getStreamFromSQL, getStreamFromAnySQL, allDefault } from '../sqlite3.js'
import { getStreamHandler } from './streamEncodedHandler.js'

const httpRequestsQueryFields = ['id', 'timestamp', 'method', 'path', 'timeElapsed', 'remoteHostname', 'statusCode']
const logsQueryFields = ['id', 'timestamp', 'severity', 'event', 'log']

const defaultPartHttpRequestsQuery = httpRequestsQueryFields.join(',')
const defaultPartLogsQuery = logsQueryFields.join(',')

const getSelectFieldsFromPart = (part) => [...new Set(part.split(','))].join(', ')
const getOrderByFieldsFromSortBy = (sortBy) => {
  const fields = [...new Set(sortBy.split(','))]
  return fields.map((field) => (field.startsWith('asc') ? `${field.slice(4, -1)} ASC` : `${field.slice(5, -1)} DESC`)).join(', ')
}

export const queryHttpRequestsHandler = getStreamHandler(async (req) => {
  const {
    query: {
      limit = 25, offset = 0, part = defaultPartHttpRequestsQuery, sort_by: sortBy = 'desc(id)',
    },
  } = req
  const selectFields = getSelectFieldsFromPart(part)
  const orderByFields = getOrderByFieldsFromSortBy(sortBy)
  const sql = `
SELECT ${selectFields}
FROM httpRequests
ORDER BY ${orderByFields}
LIMIT $limit
OFFSET $offset`
  const [{ total }] = await allDefault('SELECT COUNT(*) total FROM httpRequests')
  const dbStream = await getStreamFromSQL(sql, { $limit: parseInt(limit), $offset: parseInt(offset) }, total)
  return [dbStream]
})

export const queryLogsHandler = getStreamHandler(async (req) => {
  const {
    query: {
      limit = 25, offset = 0, part = defaultPartLogsQuery, sort_by: sortBy = 'desc(id)',
    },
  } = req
  const selectFields = getSelectFieldsFromPart(part)
  const orderByFields = getOrderByFieldsFromSortBy(sortBy)
  const sql = `
SELECT ${selectFields}
FROM applicationLogs
ORDER BY ${orderByFields}
LIMIT $limit
OFFSET $offset`
  const [{ total }] = await allDefault('SELECT COUNT(*) total FROM applicationLogs')
  const dbStream = await getStreamFromSQL(sql, { $limit: parseInt(limit), $offset: parseInt(offset) }, total)
  return [dbStream]
})

export const queryAnySQLHandler = getStreamHandler(async (req) => {
  const { body: sql } = req
  logger.info('RAW SQL QUERY', { sql })
  const dbStream = await getStreamFromAnySQL(sql, {})
  return [dbStream]
}, true)
