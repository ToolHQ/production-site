import { parseBody } from '../services/bodyParser.js'
import { mimeTypes } from '../constants.js'
import { getValidator } from '../services/validations.js'

const getPatternSplittedByComma = (fields) => {
  const fieldsStr = fields.join('|')
  return `^(${fieldsStr})(,(${fieldsStr}))*$`
}
const getPatternSplittedByCommaSortBy = (fields) => {
  const fieldsStr = fields.map((f) => `asc\\(${f}\\)`).concat(fields.map((f) => `desc\\(${f}\\)`)).join('|')
  return `^(${fieldsStr})(,(${fieldsStr}))*$`
}

const httpRequestsQueryFields = ['id', 'timestamp', 'method', 'path', 'timeElapsed', 'remoteHostname', 'statusCode']
const logsQueryFields = ['id', 'timestamp', 'severity', 'event', 'log']

const validateReq = getValidator({
  type: 'object',
  properties: {
    query: {
      type: 'object',
      properties: {
        limit: {
          type: 'number',
        },
        offset: {
          type: 'number',
        },
        part: {
          type: 'string',
          pattern: getPatternSplittedByComma(httpRequestsQueryFields),
        },
        sort_by: {
          type: 'string',
          pattern: getPatternSplittedByCommaSortBy(httpRequestsQueryFields),
        },
      },
      additionalProperties: false,
    },
  },
  additionalProperties: true,
})

const validateReqLogs = getValidator({
  type: 'object',
  properties: {
    query: {
      type: 'object',
      properties: {
        limit: {
          type: 'number',
        },
        offset: {
          type: 'number',
        },
        part: {
          type: 'string',
          pattern: getPatternSplittedByComma(logsQueryFields),
        },
        sort_by: {
          type: 'string',
          pattern: getPatternSplittedByCommaSortBy(logsQueryFields),
        },
      },
      additionalProperties: false,
    },
  },
  additionalProperties: true,
})

/**
 * @type {import('../router').RequestListener}
 */
export const validateQueryHttpRequestsHandler = (req, res) => {
  const validationErrors = validateReq(req)
  if (validationErrors) {
    res.writeHead(400, { 'Content-Type': mimeTypes.json })
      .end(JSON.stringify({ message: validationErrors.message, schemaPath: validationErrors.schemaPath }))
  }
  return validationErrors
}

/**
 * @type {import('../router').RequestListener}
 */
export const validateQueryLogsHandler = (req, res) => {
  const validationErrors = validateReqLogs(req)
  if (validationErrors) {
    res
      .writeHead(400, { 'Content-Type': mimeTypes.json })
      .end(JSON.stringify({ message: validationErrors.message, schemaPath: validationErrors.schemaPath }))
  }
  return validationErrors
}

/**
 * @type {import('../router').RequestListener}
 */
export const validateQueryAnySQLHandler = async (req, res) => {
  const sql = await parseBody(req)
  if (!sql) {
    res.writeHead(400, { 'Content-Type': mimeTypes.json })
      .end('{"message":"Input must not be empty"}')
    return true
  }
  return false
}
