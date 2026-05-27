import {
  describe,
  expect,
  test,
} from '@jest/globals'

import { fillDailyBuckets, fillHourlyBuckets } from './threatTimeseries.js'

describe('services/threatTimeseries.js', () => {
  test('fillHourlyBuckets returns 24 points with zero fill', () => {
    const now = new Date()
    now.setUTCMinutes(0, 0, 0)
    const bucket = now.toISOString().slice(0, 13).concat(':00:00Z')

    const points = fillHourlyBuckets([{ bucket, count: 9 }], 24)
    expect(points).toHaveLength(24)
    expect(points[points.length - 1]).toEqual({
      timestamp: Math.floor(now.getTime() / 1000),
      value: 9,
    })
    expect(points[0].value).toBe(0)
  })

  test('fillDailyBuckets returns 7 points with zero fill', () => {
    const today = new Date()
    today.setUTCHours(0, 0, 0, 0)
    const bucket = today.toISOString().slice(0, 10)

    const points = fillDailyBuckets([{ bucket, count: 42 }], 7)
    expect(points).toHaveLength(7)
    expect(points[points.length - 1]).toEqual({
      timestamp: Math.floor(today.getTime() / 1000),
      value: 42,
    })
  })
})
