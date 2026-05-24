import {
  describe, expect, jest, test,
} from '@jest/globals'

import { getResMock } from '../testingHelpers.js'
import { indexHandler } from './indexHandler.js'

describe('handlers/indexHandler.js', () => {
  test('Should write pudim html', () => {
    const resMock = getResMock(jest)
    indexHandler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(200)
    expect(resMock.headers).toStrictEqual({
      'Content-Type': 'text/html; charset=utf-8',
    })
    expect(resMock.body).toBe('<html><h1>Aprecie este maravilhoso pudim</h1><img src="pudim.png"></html>')
    expect(resMock.res.end).toHaveBeenCalled()
  })
})
