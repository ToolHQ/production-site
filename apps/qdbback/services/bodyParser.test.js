import { describe, expect, test } from '@jest/globals'
import { Req } from '../testingHelpers.js'

import { parseBody } from './bodyParser.js'

describe('services/bodyParser.js', () => {
  test('Should resolve with parsed json when json payload', async () => {
    const req = new Req()
    req.setHeader('content-type', 'application/json')
    const promise = parseBody(req)
    req.emit('data', Buffer.from('{"name'))
    req.emit('data', Buffer.from('":"Daniel","age"'))
    req.emit('data', Buffer.from(':27}'))
    req.emit('end')
    const body = await promise
    expect(body).toStrictEqual({
      name: 'Daniel',
      age: 27,
    })
  })

  test('Should reject when json payload but invalid JSON', async () => {
    const req = new Req()
    req.setHeader('content-type', 'application/json')
    try {
      const promise = parseBody(req)
      req.emit('data', Buffer.from('{"name'))
      req.emit('data', Buffer.from('":"Daniel",age'))
      req.emit('data', Buffer.from(':27}'))
      req.emit('end')
      await promise
      throw Error('Should Propagate Error')
    } catch (err) {
      expect(err.message).toBe('Unexpected token a in JSON at position 17')
    }
  })

  test('Should resolve with string when not json payload', async () => {
    const req = new Req()
    req.setHeader('content-type', 'text/plain')
    const promise = parseBody(req)
    req.emit('data', Buffer.from('Hello '))
    req.emit('data', Buffer.from('World'))
    req.emit('data', Buffer.from('!'))
    req.emit('end')
    const body = await promise
    expect(body).toBe('Hello World!')
  })

  test('Should not crash with properties with __proto__ attack', async () => {
    const req = new Req()
    req.setHeader('content-type', 'application/json')
    const promise = parseBody(req)
    req.emit('data', Buffer.from('{"__proto__":null,"name":{"toString":"notAFunctionThenMayCauseDoS2","valueOf":"aeee"}}'))
    req.emit('end')
    const body = await promise
    expect(body.name).toStrictEqual({
      toString: 'notAFunctionThenMayCauseDoS2',
      valueOf: 'aeee',
    })
    expect(Object.getPrototypeOf(body)).toBe(Object.prototype)
  })

  test('Should resolve with parsed json when csp-report payload', async () => {
    const req = new Req()
    req.setHeader('content-type', 'application/csp-report')
    const promise = parseBody(req)
    req.emit('data', Buffer.from(JSON.stringify({
      'csp-report': {
        'document-uri': 'https://example.com/signup.html',
        referrer: '',
        'blocked-uri': 'https://example.com/css/style.css',
        'violated-directive': 'style-src cdn.example.com',
        'original-policy': "default-src 'none'; style-src cdn.example.com; report-uri /internal/csp-reports",
        disposition: 'report',
      },
    })))
    req.emit('end')
    const body = await promise
    expect(body).toStrictEqual({
      'csp-report': {
        'document-uri': 'https://example.com/signup.html',
        referrer: '',
        'blocked-uri': 'https://example.com/css/style.css',
        'violated-directive': 'style-src cdn.example.com',
        'original-policy': "default-src 'none'; style-src cdn.example.com; report-uri /internal/csp-reports",
        disposition: 'report',
      },
    })
  })
})
