import {
  beforeAll, describe, expect, jest, test,
} from '@jest/globals'

/** @type {import('./constants.js')} */
let constants

jest.mockModule('fs', () => ({
  readFileSync: () => ({ toString: () => JSON.stringify({ commitTitle: 'Some commit', sha: 'ffb51b7e' }) }),
}))

describe('constants.test.js', () => {
  beforeAll(async () => {
    constants = await import('./constants.js')
  })

  test('Should timming cache constants of milliseconds be 1000x the seconds', () => {
    Object.entries(constants.cacheConstants.time).forEach(([entryName, { ms, s }]) => {
      expect(`${entryName} in ms = ${ms}}`).toBe(`${entryName} in ms = ${1000 * s}}`)
    })
  })

  test('Should format version from file and return it', () => {
    expect(constants.version).toBe('Some commit - ffb51b7e')
  })
})
