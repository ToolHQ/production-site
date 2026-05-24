import {
  beforeAll, describe, expect, jest, test,
} from '@jest/globals'

import { getResMock } from '../testingHelpers.js'

jest.mockModule('../services/dns.js', () => ({
  // eslint-disable-next-line no-unused-vars
  lookupServiceWithCache: jest.fn((remoteIp, remotePort) => '201-26-160-146.dial-up.telesp.net.br'),
}))

jest.mockModule('../constants.js', () => ({
  version: 'Some commit - some sha',
  mimeTypes: {
    json: 'application/json',
  },
}))
/**
 * @type {import('./debugHandler')}
 */
let debugHandlerModule

describe('handlers/debugHandler.js', () => {
  beforeAll(async () => {
    debugHandlerModule = await import('./debugHandler.js')
  })

  test('Should write debug response properly', async () => {
    const resMock = getResMock(jest, {
      req: {
        socket: {
          remoteAddress: '::ffff:201.26.160.146',
          remotePort: 59346,
          remoteFamily: 'IPv6',
          localAddress: '::ffff:172.31.65.56',
          localPort: 3443,
        },
        headers: {
          host: '52.20.74.125',
          connection: 'keep-alive',
          'sec-ch-ua': '" Not;A Brand";v="99", "Google Chrome";v="91", "Chromium";v="91"',
          'sec-ch-ua-mobile': '?0',
          'upgrade-insecure-requests': '1',
          'user-agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.101 Safari/537.36',
          accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
          'sec-fetch-site': 'none',
          'sec-fetch-mode': 'navigate',
          'sec-fetch-user': '?1',
          'sec-fetch-dest': 'document',
          'accept-encoding': 'gzip, deflate, br',
          'accept-language': 'en-US,en;q=0.9,pt-BR;q=0.8,pt;q=0.7',
        },
        httpVersion: '1.1',
        trailers: {},
        url: '/debugme',
      },
    })
    await debugHandlerModule.debugHandler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(200)
    expect(resMock.headers).toStrictEqual({
      'Content-Type': 'application/json',
    })
    expect(resMock.body).toBe(JSON.stringify({
      remoteAddress: '::ffff:201.26.160.146',
      remotePort: 59346,
      remoteFamily: 'IPv6',
      remoteHostname: '201-26-160-146.dial-up.telesp.net.br',
      localAddress: '::ffff:172.31.65.56',
      localPort: 3443,
      headers: {
        host: '52.20.74.125',
        connection: 'keep-alive',
        'sec-ch-ua': '" Not;A Brand";v="99", "Google Chrome";v="91", "Chromium";v="91"',
        'sec-ch-ua-mobile': '?0',
        'upgrade-insecure-requests': '1',
        'user-agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.101 Safari/537.36',
        accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
        'sec-fetch-site': 'none',
        'sec-fetch-mode': 'navigate',
        'sec-fetch-user': '?1',
        'sec-fetch-dest': 'document',
        'accept-encoding': 'gzip, deflate, br',
        'accept-language': 'en-US,en;q=0.9,pt-BR;q=0.8,pt;q=0.7',
      },
      httpVersion: '1.1',
      trailers: {},
      url: '/debugme',
      version: 'Some commit - some sha',
    }))
  })
})
