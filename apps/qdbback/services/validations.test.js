import { describe, expect, test } from '@jest/globals'

import { getValidator } from './validations.js'

describe('services/validations.js', () => {
  test('1. Tests for type object', () => {
    const schema = {
      type: 'object',
    }
    const validator = getValidator(schema)

    let testInput = {}
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = null
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected object but got null', schemaPath: '#/type' } })

    testInput = undefined
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected object but got undefined', schemaPath: '#/type' } })

    testInput = 1
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected object but got number', schemaPath: '#/type' } })

    testInput = 'abc'

    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected object but got string', schemaPath: '#/type' } })

    testInput = false
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected object but got boolean', schemaPath: '#/type' } })

    testInput = []
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected object but got array', schemaPath: '#/type' } })
  })

  test('2. Tests for type number', () => {
    const schema = {
      type: 'number',
    }
    const validator = getValidator(schema)

    let testInput = 1
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = {}
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected number but got object', schemaPath: '#/type' } })

    testInput = null
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected number but got null', schemaPath: '#/type' } })

    testInput = undefined
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected number but got undefined', schemaPath: '#/type' } })

    testInput = false
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected number but got boolean', schemaPath: '#/type' } })

    testInput = []
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected number but got array', schemaPath: '#/type' } })

    // Custom rule, accept casted values
    testInput = '2'
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = '-1'
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = 'abc'
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected number but got string', schemaPath: '#/type' } })

    testInput = ''
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected number but got string', schemaPath: '#/type' } })

    testInput = '9'.repeat(309)
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected number but got infinity', schemaPath: '#/type' } })

    testInput = `-${'9'.repeat(309)}`
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected number but got infinity', schemaPath: '#/type' } })

    testInput = NaN
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected number but got NaN', schemaPath: '#/type' } })
  })

  test('3. Tests for type string', () => {
    const schema = {
      type: 'string',
    }
    const validator = getValidator(schema)

    let testInput = 'abc'
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = {}
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected string but got object', schemaPath: '#/type' } })

    testInput = null
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected string but got null', schemaPath: '#/type' } })

    testInput = undefined
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected string but got undefined', schemaPath: '#/type' } })

    testInput = 1
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected string but got number', schemaPath: '#/type' } })

    testInput = false
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected string but got boolean', schemaPath: '#/type' } })

    testInput = []
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected string but got array', schemaPath: '#/type' } })
  })

  test('4. Tests for type boolean', () => {
    const schema = {
      type: 'boolean',
    }
    const validator = getValidator(schema)

    let testInput = false
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = {}
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected boolean but got object', schemaPath: '#/type' } })

    testInput = null
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected boolean but got null', schemaPath: '#/type' } })

    testInput = undefined
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected boolean but got undefined', schemaPath: '#/type' } })

    testInput = 1
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected boolean but got number', schemaPath: '#/type' } })

    testInput = 'abc'
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected boolean but got string', schemaPath: '#/type' } })

    testInput = []
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected boolean but got array', schemaPath: '#/type' } })
  })

  test('5. Tests for type object with additionalProperties false and no properties at all', () => {
    const schema = {
      type: 'object',
      additionalProperties: false,
    }
    const validator = getValidator(schema)

    let testInput = {}
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = null
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected object but got null', schemaPath: '#/type' } })

    testInput = undefined
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: { message: 'Invalid type. Expected object but got undefined', schemaPath: '#/type' } })

    testInput = { a: 'value' }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Property \'a\' has not been defined and the schema does not allow additional properties.',
          schemaPath: '#/additionalProperties',
        },
      })

    testInput = { toString: 'I will try to break u' }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Property \'toString\' has not been defined and the schema does not allow additional properties.',
          schemaPath: '#/additionalProperties',
        },
      })
  })

  test('6. Tests for type object with primitive properties', () => {
    const schema = {
      type: 'object',
      properties: {
        numberProp: {
          type: 'number',
        },
        stringProp: {
          type: 'string',
        },
        booleanProp: {
          type: 'boolean',
        },
        nestedProp: {
          type: 'object',
          properties: {
            nestedNumberProp: {
              type: 'number',
            },
            nestedStringProp: {
              type: 'string',
            },
            nestedBooleanProp: {
              type: 'boolean',
            },
          },
        },
      },
    }
    const validator = getValidator(schema)

    let testInput = {}
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = null
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Invalid type. Expected object but got null',
          schemaPath: '#/type',
        },
      })

    testInput = undefined
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Invalid type. Expected object but got undefined',
          schemaPath: '#/type',
        },
      })

    testInput = { notDefined: 'value' }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = { stringProp: 123 }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Invalid type. Expected string but got number',
          schemaPath: '#/properties/stringProp/type',
        },
      })

    testInput = { numberProp: '123a' }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Invalid type. Expected number but got string',
          schemaPath: '#/properties/numberProp/type',
        },
      })

    testInput = { nestedProp: {} }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = { nestedProp: { nestedNumberProp: 42 } }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = { nestedProp: [] }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Invalid type. Expected object but got array',
          schemaPath: '#/properties/nestedProp/type',
        },
      })

    testInput = { numberProp: 1234, nestedProp: { nestedNumberProp: 'abc' } }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Invalid type. Expected number but got string',
          schemaPath: '#/properties/nestedProp/properties/nestedNumberProp/type',
        },
      })

    testInput = { numberProp: 1234, nestedProp: { nestedNumberProp: NaN } }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Invalid type. Expected number but got NaN',
          schemaPath: '#/properties/nestedProp/properties/nestedNumberProp/type',
        },
      })

    testInput = { numberProp: 1234, nestedProp: { nestedNumberProp: Infinity } }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Invalid type. Expected number but got infinity',
          schemaPath: '#/properties/nestedProp/properties/nestedNumberProp/type',
        },
      })

    testInput = { numberProp: 1234, nestedProp: { nestedBooleanProp: 'abc' } }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Invalid type. Expected boolean but got string',
          schemaPath: '#/properties/nestedProp/properties/nestedBooleanProp/type',
        },
      })

    testInput = { numberProp: 1234, nestedProp: { nestedStringProp: Infinity } }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Invalid type. Expected string but got number',
          schemaPath: '#/properties/nestedProp/properties/nestedStringProp/type',
        },
      })
  })

  test('7. Tests for type object with required properties', () => {
    const schema = {
      type: 'object',
      properties: {
        notReq: {
          type: 'string',
        },
        stringProp: {
          type: 'string',
        },
      },
      required: ['stringProp'],
    }
    const validator = getValidator(schema)

    let testInput = { stringProp: 'value' }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = { a: 'value' }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Required properties are missing from object: stringProp',
          schemaPath: '#/required',
        },
      })

    testInput = { stringProp: 'value', notReq: 1 }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Invalid type. Expected string but got number',
          schemaPath: '#/properties/notReq/type',
        },
      })
  })

  test('8. Tests for type object with additional properties', () => {
    const schema = {
      type: 'object',
      properties: {
        notReq: {
          type: 'string',
        },
        stringProp: {
          type: 'string',
        },
      },
      additionalProperties: false,
    }
    const validator = getValidator(schema)

    let testInput = { stringProp: 'value' }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = { a: 'value' }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: "Property 'a' has not been defined and the schema does not allow additional properties.",
          schemaPath: '#/additionalProperties',
        },
      })
  })

  test('9. Tests for type object with additional properties for nested object', () => {
    const schema = {
      type: 'object',
      properties: {
        nestedProp: {
          type: 'object',
          properties: {
            notReq: {
              type: 'string',
            },
            stringProp: {
              type: 'string',
            },
          },
          additionalProperties: false,
          required: ['stringProp'],
        },
      },
    }
    const validator = getValidator(schema)

    let testInput = { nestedProp: { notReq: 'abc', stringProp: 'cde' } }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = { nestedProp: { stringProp: 'cde' } }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = { nestedProp: { notReq: 123, stringProp: 'cde' } }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Invalid type. Expected string but got number',
          schemaPath: '#/properties/nestedProp/properties/notReq/type',
        },
      })

    testInput = { nestedProp: { notReq: 'cde', stringProp: 123 } }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Invalid type. Expected string but got number',
          schemaPath: '#/properties/nestedProp/properties/stringProp/type',
        },
      })

    testInput = { nestedProp: { notReq: 'abc', stringProp: 'cde', additionalProp: {} } }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: "Property 'additionalProp' has not been defined and the schema does not allow additional properties.",
          schemaPath: '#/properties/nestedProp/additionalProperties',
        },
      })

    testInput = { nestedProp: {} }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Required properties are missing from object: stringProp',
          schemaPath: '#/properties/nestedProp/required',
        },
      })

    // TODO: Make it work
    // testInput = {}
    // expect({ schema, testInput, error: validator(testInput) })
    //   .toStrictEqual({
    //     schema,
    //     testInput,
    //     error: false,
    //   })
  })

  test('10. Validate schema of qs limit and offset properly', () => {
    const schema = {
      type: 'object',
      properties: {
        query: {
          type: 'object',
          properties: {
            limit: {
              type: 'number',
            },
            offset: {
              type: 'number',
            },
          },
          additionalProperties: false,
        },
      },
      additionalProperties: true,
    }
    const validator = getValidator(schema)

    let testInput = { body: {} }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = { query: {} }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = { query: { limit: 1 } }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = { query: { offset: 55 } }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({ schema, testInput, error: false })

    testInput = { query: { offset: 'a' } }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Invalid type. Expected number but got string',
          schemaPath: '#/properties/query/properties/offset/type',
        },
      })

    testInput = { query: { offset: { toString: 'virus' } } }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: 'Invalid type. Expected number but got object',
          schemaPath: '#/properties/query/properties/offset/type',
        },
      })

    testInput = { query: { forbbiden: { toString: 'virus' } } }
    expect({ schema, testInput, error: validator(testInput) })
      .toStrictEqual({
        schema,
        testInput,
        error: {
          message: "Property 'forbbiden' has not been defined and the schema does not allow additional properties.",
          schemaPath: '#/properties/query/additionalProperties',
        },
      })
  })
})
