import {
  describe,
  expect,
  test,
} from '@jest/globals'

import zlib from 'zlib'
import { PassThrough } from 'stream'
import { getEncoder, getEncoding } from './encoding.js'

describe('services/encoding.js', () => {
  describe('#getEncoder', () => {
    test('Should return gzip stream encoder when name=gzip', () => {
      const encoder = getEncoder('gzip')
      expect(encoder).toBeInstanceOf(zlib.Gzip)
    })

    test('Should return gzip stream encoder when name=deflate', () => {
      const encoder = getEncoder('deflate')
      expect(encoder).toBeInstanceOf(zlib.Deflate)
    })

    test('Should return gzip stream encoder when name=br', () => {
      const encoder = getEncoder('br')
      expect(encoder).toBeInstanceOf(zlib.BrotliCompress)
    })

    test('Should return PassThrough stream encoder when name=identity', () => {
      const encoder = getEncoder('identity')
      expect(encoder).toBeInstanceOf(PassThrough)
    })

    test('Should return null when unknown encoder name provided', () => {
      const encoder = getEncoder('unknown')
      expect(encoder).toBe(null)
    })
  })

  describe('#getEncoding', () => {
    test('Should parse correctly \'deflate, gzip;q=1.0, *;q=0.5 \' and choose \'deflate\'', async () => {
      const encoding = getEncoding('deflate, gzip;q=1.0, *;q=0.5 ')
      expect(encoding).toBe('deflate')
    })

    test('Should parse correctly \'deflate;q=0.99, gzip;q=1.0, *;q=0.5 \' and choose \'gzip\'', async () => {
      const encoding = getEncoding('deflate;q=0.99, gzip;q=1.0, *;q=0.5 ')
      expect(encoding).toBe('gzip')
    })

    test('Should parse correctly \'gzip, deflate, br\' and choose \'gzip\'', async () => {
      const encoding = getEncoding('gzip, deflate, br')
      expect(encoding).toBe('gzip')
    })

    test('Should parse correctly \' br ,   *;q=0\' and choose \'br\'', async () => {
      const encoding = getEncoding('br,   *;q=0')
      expect(encoding).toBe('br')
    })

    test('Should parse correctly \'bzip2,   *;q=0\' and return null since bzip2 is unsupported', async () => {
      const encoding = getEncoding('bzip2,   *;q=0')
      expect(encoding).toBe(null)
    })

    test('Should parse correctly \'bzip2, gzip;q=0.0, *;q=0.5\' and return other encoding than gzip or bzip2', async () => {
      const encoding = getEncoding('bzip2, gzip;q=0.0, *;q=0.5')
      expect(encoding).not.toBe(null)
      expect(encoding).not.toBe('bzip2')
      expect(encoding).not.toBe('gzip')
    })

    test('Should parse correctly \'bzip2, gzip;q=0.0, br;q=0, deflate;q=0, identity;q=0, *;q=0.5\' and return no encoding since all available supported negated', async () => {
      const encoding = getEncoding('bzip2, gzip;q=0.0, br;q=0, deflate;q=0, identity;q=0, *;q=0.5')
      expect(encoding).toBe(null)
    })

    test('Should parse correctly \'deflate,   gzip ; q=0\' and return deflate', async () => {
      const encoding = getEncoding('deflate,   gzip ; q=0')
      expect(encoding).toBe('deflate')
    })

    test('Should parse correctly \';q=1.0\' and return some encoding', async () => {
      const encoding = getEncoding(';q=1.0')
      expect(encoding).not.toBe(null)
    })

    test('Should choose \'identity\' for empty string', async () => {
      const encoding = getEncoding('')
      expect(encoding).toBe('identity')
    })

    test('Should choose \'identity\' for blank string', async () => {
      const encoding = getEncoding('   ')
      expect(encoding).toBe('identity')
    })
  })
})
