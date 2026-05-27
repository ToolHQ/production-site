import {
  describe,
  expect,
  test,
} from '@jest/globals'

import { isReadOnlySelect } from './sqlGuard.js'

describe('services/sqlGuard.js', () => {
  test('allows simple SELECT', () => {
    expect(isReadOnlySelect('SELECT id FROM httpRequests LIMIT 1')).toBe(true)
  })

  test('blocks destructive statements', () => {
    expect(isReadOnlySelect('DELETE FROM httpRequests')).toBe(false)
    expect(isReadOnlySelect('SELECT 1; DROP TABLE httpRequests')).toBe(false)
  })

  test('blocks non-select', () => {
    expect(isReadOnlySelect('INSERT INTO httpRequests VALUES (1)')).toBe(false)
  })
})
