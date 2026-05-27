import { describe, expect, test } from '@jest/globals'
import { finalizeToJSON, stringifyKeyPair, stringifyPlainMap } from './stringify.js'

describe('services/stringify', () => {
  test('Should stringify simple properties properly', () => {
    const date = new Date()
    expect(finalizeToJSON([
      stringifyKeyPair('anUndefined', undefined),
      stringifyKeyPair('aNull', null),
      stringifyKeyPair('aFalseBoolean', false),
      stringifyKeyPair('aTrueBoolean', true),
      stringifyKeyPair('anInteger', 12345),
      stringifyKeyPair('aFloat', 10.45),
      stringifyKeyPair('aDate', date.toISOString()),
      stringifyKeyPair('aString', 'Hello world!'),
      stringifyKeyPair('aQuotedString', 'The "quick" brown fox jumps over the lazy "dog"'),
    ])).toBe(JSON.stringify({
      anUndefined: undefined,
      aNull: null,
      aFalseBoolean: false,
      aTrueBoolean: true,
      anInteger: 12345,
      aFloat: 10.45,
      aDate: date,
      aString: 'Hello world!',
      aQuotedString: 'The "quick" brown fox jumps over the lazy "dog"',
    }))
  })

  test('Should have some known limitations', () => {
    expect(stringifyKeyPair('aNaN', NaN)).toBe('"aNaN":NaN')
    expect(stringifyKeyPair('aInfinity', Infinity)).toBe('"aInfinity":Infinity')
    expect(stringifyKeyPair('aNegativeInfinity', -Infinity)).toBe('"aNegativeInfinity":-Infinity')
  })

  test('Should stringify some nested properties properly', () => {
    expect(finalizeToJSON([
      stringifyKeyPair('name', 'Daniel'),
      stringifyKeyPair('age', 27),
      stringifyKeyPair('money', null),
      stringifyKeyPair('physical', stringifyPlainMap({
        eyes: 'brown',
        hair: 'black',
        height: 174,
        weight: 80.5,
        missing: undefined,
      }), true),
    ])).toBe(JSON.stringify({
      name: 'Daniel',
      age: 27,
      money: null,
      physical: {
        eyes: 'brown',
        hair: 'black',
        height: 174,
        weight: 80.5,
        missing: undefined,
      },
    }))
  })
})
