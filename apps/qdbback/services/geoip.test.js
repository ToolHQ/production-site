import {
  describe,
  expect,
  test,
} from '@jest/globals'

import { isPrivateIp, lookupCountry } from './geoip.js'

describe('services/geoip.js', () => {
  test('marks private IPs', () => {
    expect(isPrivateIp('127.0.0.1')).toBe(true)
    expect(isPrivateIp('10.0.0.1')).toBe(true)
    expect(isPrivateIp('192.168.1.1')).toBe(true)
  })

  test('resolves public IP to country code', () => {
    // Google DNS — stable public IP with known geo data
    const country = lookupCountry('8.8.8.8')
    expect(country).toBe('US')
  })

  test('returns null for private IP', () => {
    expect(lookupCountry('127.0.0.1')).toBeNull()
  })
})
