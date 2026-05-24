import { describe, expect, test } from '@jest/globals'
import {
  port,
  portHttps,
  portAdmin,
  isProduction,
} from './config.js'

describe('config.test.js', () => {
  test('Should define all properties properly', () => {
    expect(port).toBe(3000)
    expect(portHttps).toBe(3443)
    expect(portAdmin).toBe(3500)
  })

  test('Should not run tests at production server', () => {
    expect(isProduction).toBe(false)
  })
})
