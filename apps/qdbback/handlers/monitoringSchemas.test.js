import {
  describe,
  expect,
  jest,
  test,
} from '@jest/globals'

import { getResMock } from '../testingHelpers.js'
import { buildReq } from '../router.js'
import { validateQueryHttpRequestsHandler, validateQueryLogsHandler, validateQueryAnySQLHandler } from './monitoringSchemas.js'

describe('handlers/monitoringSchemas.js', () => {
  describe('#validateQueryHttpRequestsHandler', () => {
    test('Should give no errors when payload is valid', async () => {
      const resMock = getResMock(jest, {
        req: {
          url: 'api/monitor/requests?part=id,timestamp,method,path,timeElapsed,remoteHostname,statusCode&sort_by=desc(id),desc(method)&limit=20&offset=10',
        },
      })
      buildReq(resMock.req)
      const errors = await validateQueryHttpRequestsHandler(resMock.req, resMock.res)
      expect(errors).toBe(false)
    })

    test('Should give errors when invalid part pattern', async () => {
      const resMock = getResMock(jest, {
        req: {
          url: 'api/monitor/requests?part=id,password',
        },
      })
      buildReq(resMock.req)
      const errors = await validateQueryHttpRequestsHandler(resMock.req, resMock.res)
      expect(errors).toBeTruthy()
      expect(resMock.statusCode).toBe(400)
      expect(JSON.parse(resMock.body).schemaPath).toBe('#/properties/query/properties/part/pattern')
    })

    test('Should give errors when invalid limit pattern', async () => {
      const resMock = getResMock(jest, {
        req: {
          url: 'api/monitor/requests?limit=a',
        },
      })
      buildReq(resMock.req)
      const errors = await validateQueryHttpRequestsHandler(resMock.req, resMock.res)
      expect(errors).toBeTruthy()
      expect(resMock.statusCode).toBe(400)
      expect(JSON.parse(resMock.body).schemaPath).toBe('#/properties/query/properties/limit/type')
    })

    test('Should give errors when invalid offset pattern', async () => {
      const resMock = getResMock(jest, {
        req: {
          url: 'api/monitor/requests?offset=a',
        },
      })
      buildReq(resMock.req)
      const errors = await validateQueryHttpRequestsHandler(resMock.req, resMock.res)
      expect(errors).toBeTruthy()
      expect(resMock.statusCode).toBe(400)
      expect(JSON.parse(resMock.body).schemaPath).toBe('#/properties/query/properties/offset/type')
    })

    test('Should give errors when invalid sort_by pattern', async () => {
      const resMock = getResMock(jest, {
        req: {
          url: 'api/monitor/requests?sort_by=desc(logs)',
        },
      })
      buildReq(resMock.req)
      const errors = await validateQueryHttpRequestsHandler(resMock.req, resMock.res)
      expect(errors).toBeTruthy()
      expect(resMock.statusCode).toBe(400)
      expect(JSON.parse(resMock.body).schemaPath).toBe('#/properties/query/properties/sort_by/pattern')
    })

    test('Should give errors when extra parameter', async () => {
      const resMock = getResMock(jest, {
        req: {
          url: 'api/monitor/requests?unknownParam=true',
        },
      })
      buildReq(resMock.req)
      const errors = await validateQueryHttpRequestsHandler(resMock.req, resMock.res)
      expect(errors).toBeTruthy()
      expect(resMock.statusCode).toBe(400)
      expect(JSON.parse(resMock.body).schemaPath).toBe('#/properties/query/additionalProperties')
    })

    test('Should ignore prototype pollution params attempts', async () => {
      const resMock = getResMock(jest, {
        req: {
          url: 'api/monitor/requests?toString=iwilltrytobreakyou',
        },
      })
      buildReq(resMock.req)
      const errors = await validateQueryHttpRequestsHandler(resMock.req, resMock.res)
      expect(errors).toEqual(false)
    })
  })

  describe('#validateQueryLogsHandler', () => {
    test('Should give no errors when payload is valid', async () => {
      const resMock = getResMock(jest, {
        req: {
          url: 'api/monitor/logs?part=id,timestamp,severity,event,log&sort_by=desc(id),desc(severity)&limit=20&offset=10',
        },
      })
      buildReq(resMock.req)
      const errors = await validateQueryLogsHandler(resMock.req, resMock.res)
      expect(errors).toBe(false)
    })

    test('Should give errors when invalid part pattern', async () => {
      const resMock = getResMock(jest, {
        req: {
          url: 'api/monitor/logs?part=id,password',
        },
      })
      buildReq(resMock.req)
      const errors = await validateQueryLogsHandler(resMock.req, resMock.res)
      expect(errors).toBeTruthy()
      expect(resMock.statusCode).toBe(400)
      expect(JSON.parse(resMock.body).schemaPath).toBe('#/properties/query/properties/part/pattern')
    })

    test('Should give errors when invalid limit pattern', async () => {
      const resMock = getResMock(jest, {
        req: {
          url: 'api/monitor/logs?limit=a',
        },
      })
      buildReq(resMock.req)
      const errors = await validateQueryLogsHandler(resMock.req, resMock.res)
      expect(errors).toBeTruthy()
      expect(resMock.statusCode).toBe(400)
      expect(JSON.parse(resMock.body).schemaPath).toBe('#/properties/query/properties/limit/type')
    })

    test('Should give errors when invalid offset pattern', async () => {
      const resMock = getResMock(jest, {
        req: {
          url: 'api/monitor/logs?offset=a',
        },
      })
      buildReq(resMock.req)
      const errors = await validateQueryLogsHandler(resMock.req, resMock.res)
      expect(errors).toBeTruthy()
      expect(resMock.statusCode).toBe(400)
      expect(JSON.parse(resMock.body).schemaPath).toBe('#/properties/query/properties/offset/type')
    })

    test('Should give errors when invalid sort_by pattern', async () => {
      const resMock = getResMock(jest, {
        req: {
          url: 'api/monitor/logs?sort_by=desc(password)',
        },
      })
      buildReq(resMock.req)
      const errors = await validateQueryLogsHandler(resMock.req, resMock.res)
      expect(errors).toBeTruthy()
      expect(resMock.statusCode).toBe(400)
      expect(JSON.parse(resMock.body).schemaPath).toBe('#/properties/query/properties/sort_by/pattern')
    })

    test('Should give errors when extra parameter', async () => {
      const resMock = getResMock(jest, {
        req: {
          url: 'api/monitor/logs?unknownParam=true',
        },
      })
      buildReq(resMock.req)
      const errors = await validateQueryLogsHandler(resMock.req, resMock.res)
      expect(errors).toBeTruthy()
      expect(resMock.statusCode).toBe(400)
      expect(JSON.parse(resMock.body).schemaPath).toBe('#/properties/query/additionalProperties')
    })

    test('Should ignore prototype pollution params attempts', async () => {
      const resMock = getResMock(jest, {
        req: {
          url: 'api/monitor/logs?toString=iwilltrytobreakyou',
        },
      })
      buildReq(resMock.req)
      const errors = await validateQueryLogsHandler(resMock.req, resMock.res)
      expect(errors).toEqual(false)
    })
  })

  describe('#validateQueryAnySQLHandler', () => {
    test('Should give no errors when payload is valid', async () => {
      const resMock = getResMock(jest, {
        req: {
          url: 'api/monitor/sql',
        },
      })
      const handlerPromise = validateQueryAnySQLHandler(resMock.req, resMock.res)
      resMock.req.emit('data', Buffer.from('SELECT * FROM httpRequests LIMIT 10'))
      resMock.req.emit('end')
      const errors = await handlerPromise
      expect(errors).toBe(false)
    })

    test('Should give errors when payload is empty', async () => {
      const resMock = getResMock(jest, {
        req: {
          url: 'api/monitor/sql',
        },
      })
      const handlerPromise = validateQueryAnySQLHandler(resMock.req, resMock.res)
      resMock.req.emit('data', Buffer.from(''))
      resMock.req.emit('end')
      const errors = await handlerPromise
      expect(errors).toBeTruthy()
      expect(resMock.statusCode).toBe(400)
      expect(JSON.parse(resMock.body).message).toBe('Input must not be empty')
    })
  })
})
