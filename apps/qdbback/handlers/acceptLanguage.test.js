import {
  describe, expect, jest, test,
} from '@jest/globals'

import { getResMock } from '../testingHelpers.js'

import { acceptLanguageHandler } from './acceptLanguage.js'

describe('handlers/acceptLanguage.js', () => {
  test('Should end response with accepted languages sorted and status code 200', () => {
    const resMock = getResMock(jest, {
      req: {
        headers: {
          'accept-language': 'en-US,en;q=0.9,pt-BR;q=0.8,pt;q=0.7',
        },
      },
    })
    acceptLanguageHandler(resMock.req, resMock.res)
    expect(resMock.statusCode).toBe(200)
    expect(resMock.headers).toStrictEqual({
      'Content-Type': 'application/json',
    })
    expect(resMock.body).toBe(JSON.stringify({
      languages: [
        {
          locale: 'en-US',
          weight: 1,
        },
        {
          locale: 'en',
          weight: 0.9,
        },
        {
          locale: 'pt-BR',
          weight: 0.8,
        },
        {
          locale: 'pt',
          weight: 0.7,
        },
      ],
    }))
    expect(resMock.res.end).toHaveBeenCalled()
  })
})
