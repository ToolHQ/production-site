import { Stream } from 'stream'

export class Req extends Stream {
  constructor(options) {
    super(options)
    this.socket = {}
    this.trailers = {}
    this.headers = {}
    this.method = 'GET'
    this.url = ''
  }

  setHeader(key, value) {
    if (key !== '__proto__') {
      this.headers[String(key)] = value
    }
  }
}

const defaultReq = new Req()

/**
 * @param {import('@jest/globals').jest} jest
 * @returns
 */
export const getResMock = (jest, { req = defaultReq } = { req: defaultReq }) => {
  let reqObj = req
  if (!(reqObj instanceof Req)) {
    reqObj = new Req()
    const reqInput = req || {}
    Object.entries((reqInput.headers) || {}).forEach(([key, value]) => reqObj.setHeader(key, value))
    if (reqInput.socket) reqObj.socket = reqInput.socket
    if (reqInput.method) reqObj.method = reqInput.method
    if (reqInput.url) reqObj.url = reqInput.url
    if (reqInput.trailers) reqObj.trailers = reqInput.trailers
    if (reqInput.httpVersion) reqObj.httpVersion = reqInput.httpVersion
    if (reqInput.url) reqObj.url = reqInput.url
  }

  let body = ''
  let statusCode = 200
  let headers = {}
  let hasEnded = false
  let endPromiseResolve
  const endPromise = new Promise((resolve) => {
    endPromiseResolve = resolve
  })
  let finishPromiseResolve
  const finishPromise = new Promise((resolve) => {
    finishPromiseResolve = resolve
  })
  const res = {
    setHeader: jest.fn((key, value) => {
      if (key !== '__proto__') {
        headers[String(key)] = value
      }
    }),
    end: jest.fn((chunk = '') => {
      if (!hasEnded) {
        body += chunk.toString()
      }
      hasEnded = true
      endPromiseResolve()
    }),
    finish: jest.fn(() => {
      finishPromiseResolve()
    }),
    writeHead: jest.fn(function writeHead(statusCodeParam, headersParam = {}) {
      statusCode = statusCodeParam
      headers = { ...headers, ...headersParam }
      return this
    }),
    write: jest.fn((chunk) => {
      if (!hasEnded) {
        body += chunk.toString()
      }
    }),
    get statusCode() {
      return statusCode
    },
    set statusCode(statusCodeParam) {
      statusCode = statusCodeParam
    },
    eventListeners: new Map(),
    eventListenersOnce: new Map(),
    on: function on(event, callback) {
      if (!['unpipe', 'error', 'close', 'end', 'finish'].includes(event)) {
        throw Error(`onEvent ${event} Not Implemented!!`)
      }
      // console.log(`onEvent ${event} called`)
      if (this.eventListeners.has(event)) {
        return this.eventListeners.set(event, [...this.eventListeners.get(event), callback])
      }
      return this.eventListeners.set(event, [callback])
    },
    once: function once(event, callback) {
      if (!['close', 'finish'].includes(event)) {
        throw Error(`onceEvent ${event} Not Implemented!!`)
      }
      // console.log(`onceEvent ${event} called`)
      if (this.eventListenersOnce.has(event)) {
        return this.eventListenersOnce.set(event, [...this.eventListenersOnce.get(event), callback])
      }
      return this.eventListenersOnce.set(event, [callback])
    },
    emit: function emit(event, data) {
      const eventListeners = this.eventListeners.get(event)
      if (Array.isArray(eventListeners) && eventListeners.length) {
        eventListeners.forEach((eventListener) => eventListener(data))
      }
      const eventListenersOnce = this.eventListenersOnce.get(event)
      if (Array.isArray(eventListenersOnce) && eventListenersOnce.length) {
        this.eventListenersOnce.delete(event)
        eventListenersOnce.forEach((eventListener) => eventListener(data))
      }
      if (event === 'end') {
        this.end(data)
      } else if (event === 'finish') {
        this.finish(data)
      } else if (event === 'write') {
        this.write(data)
      }
    },
    removeListener: function removeListener(event) {
      if (!['close', 'finish'].includes(event)) {
        throw Error(`removeListener ${event} Not Implemented!!`)
      }
      this.eventListeners.delete(event)
      this.eventListenersOnce.delete(event)
    },
  }
  return {
    req: reqObj,
    res,
    endPromise,
    finishPromise,
    getStatusCode: () => statusCode,
    getHeaders: () => headers,
    getBody: () => body,
    get statusCode() { return statusCode },
    get headers() { return headers },
    get body() { return body },
  }
}
