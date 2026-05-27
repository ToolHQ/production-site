import { describe, expect, test } from '@jest/globals'

import { classifyRequest } from './classifyRequest.js'

describe('services/classifyRequest.js', () => {
  test('classifies .env probes', () => {
    expect(classifyRequest({ path: '/.env', userAgent: 'curl/8.0' }))
      .toBe('env-leak')
  })

  test('classifies phpunit RCE path', () => {
    const result = classifyRequest({
      path: '/vendor/phpunit/phpunit/src/Util/PHP/eval-stdin.php',
      userAgent: 'Mozilla/5.0',
    })
    expect(result).toContain('phpunit-rce')
  })

  test('classifies scanner user agents', () => {
    expect(classifyRequest({ path: '/', userAgent: 'Mozilla/5.0 zgrab/0.x' }))
      .toContain('scanner:zgrab')
    expect(classifyRequest({ path: '/api', userAgent: 'CensysInspect/1.1' }))
      .toContain('scanner:censys')
  })

  test('root path gets probe:root', () => {
    expect(classifyRequest({ path: '/', userAgent: 'curl/8.0' }))
      .toContain('probe:root')
  })

  test('unknown paths are unclassified', () => {
    expect(classifyRequest({ path: '/unique-custom-path-xyz', userAgent: 'curl/8.0' }))
      .toBe('unclassified')
  })

  test('combines path and UA tags', () => {
    const result = classifyRequest({
      path: '/.env',
      userAgent: 'Mozilla/5.0 zgrab/0.x',
    })
    expect(result).toContain('env-leak')
    expect(result).toContain('scanner:zgrab')
  })
})
