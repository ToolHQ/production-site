import { describe, expect, test } from '@jest/globals'
import { parseAcceptLanguageHeader } from './parseAcceptLanguageHeader.js'

describe('services/parseAcceptLanguageHeader.js', () => {
  test('Should parse Chrome/91.0.4472.101 Accept-Language sample value', () => {
    const acceptLanguageHandlerStr = 'en-US,en;q=0.9,pt-BR;q=0.8,pt;q=0.7'
    const parsed = parseAcceptLanguageHeader(acceptLanguageHandlerStr)
    expect(parsed).toStrictEqual([
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
    ])
  })

  test('Should parse unsorted and duplicated Accept-Language value and sort it', () => {
    const acceptLanguageHandlerStr = 'en;q=0.9,pt-BR;q=0.8,en-US,ru;q=0.9,en;q=0.9,pt;q=0.7'
    const parsed = parseAcceptLanguageHeader(acceptLanguageHandlerStr)
    expect(parsed).toStrictEqual([
      {
        locale: 'en-US',
        weight: 1,
      },
      {
        locale: 'en',
        weight: 0.9,
      },
      {
        locale: 'ru',
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
    ])
  })
})
