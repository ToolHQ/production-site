import {
  beforeAll,
  beforeEach,
  describe,
  expect,
  jest,
  test,
} from '@jest/globals'

const mockedLookupServiceFunction = jest.fn((ip, port, callback) => callback(null, 'mockedValue'))

jest.mockModule('dns', () => ({
  lookupService: mockedLookupServiceFunction,
}))

/** @type {import('./dns.js').lookupServiceWithCache} */
let lookupServiceWithCache
/** @type {import('./dns.js').getLookupResults} */
let getLookupResults

jest.useFakeTimers()

describe('services/dns.js', () => {
  beforeAll(async () => {
    const dns = await import('./dns.js')
    lookupServiceWithCache = dns.lookupServiceWithCache
    getLookupResults = dns.getLookupResults
  })

  beforeEach(() => {
    jest.advanceTimersByTime(60000)
  })

  describe('#lookupServiceWithCache', () => {
    test('Should lookupServiceWithCache properly cache it then expire after 1min', async () => {
      const hostname = await lookupServiceWithCache('127.0.0.1', 8080)
      expect(hostname).toBe('mockedValue')
      expect(getLookupResults().get('127.0.0.1')).toBe('mockedValue')
      jest.advanceTimersByTime(60000)
      expect(getLookupResults().get('127.0.0.1')).toBeUndefined()
    })

    test('Should lookupServiceWithCache not throw Error when lookupService fails and return null', async () => {
      mockedLookupServiceFunction.mockImplementationOnce((ip, port, callback) => callback(Error('Some EAI_AGAIN Error'), null))
      const hostname = await lookupServiceWithCache('127.0.0.1', 8080)
      expect(hostname).toBeNull()
    })

    test('Should lookupServiceWithCache properly cache it and consult cache', async () => {
      const hostname = await lookupServiceWithCache('127.0.0.1', 8080)
      expect(hostname).toBe('mockedValue')
      jest.advanceTimersByTime(30000)
      expect(getLookupResults().get('127.0.0.1')).toBe('mockedValue')
      const hostname2 = await lookupServiceWithCache('127.0.0.1', 8080)
      expect(hostname2).toBe('mockedValue')
      jest.advanceTimersByTime(30000)
      expect(getLookupResults().get('127.0.0.1')).toBeUndefined()
    })
  })
})
