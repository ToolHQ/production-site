import { allDefault } from '../sqlite3.js'

const HOURLY_SQL = `
SELECT strftime('%Y-%m-%dT%H:00:00Z', timestamp) AS bucket, COUNT(*) AS count
FROM httpRequests
WHERE timestamp >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-24 hours')
GROUP BY bucket
ORDER BY bucket ASC`

const DAILY_SQL = `
SELECT strftime('%Y-%m-%d', timestamp) AS bucket, COUNT(*) AS count
FROM httpRequests
WHERE timestamp >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-7 days')
GROUP BY bucket
ORDER BY bucket ASC`

/**
 * @param {Array<{ bucket: string, count: number }>} rows
 * @param {number} hours
 * @returns {Array<{ timestamp: number, value: number }>}
 */
export function fillHourlyBuckets(rows, hours = 24) {
  const counts = new Map(rows.map((row) => [row.bucket, row.count]))
  const now = new Date()
  now.setUTCMinutes(0, 0, 0)

  const points = []
  for (let offset = hours - 1; offset >= 0; offset -= 1) {
    const bucketDate = new Date(now.getTime() - offset * 60 * 60 * 1000)
    const bucket = bucketDate.toISOString().slice(0, 13).concat(':00:00Z')
    points.push({
      timestamp: Math.floor(bucketDate.getTime() / 1000),
      value: counts.get(bucket) ?? 0,
    })
  }
  return points
}

/**
 * @param {Array<{ bucket: string, count: number }>} rows
 * @param {number} days
 * @returns {Array<{ timestamp: number, value: number }>}
 */
export function fillDailyBuckets(rows, days = 7) {
  const counts = new Map(rows.map((row) => [row.bucket, row.count]))
  const today = new Date()
  today.setUTCHours(0, 0, 0, 0)

  const points = []
  for (let offset = days - 1; offset >= 0; offset -= 1) {
    const bucketDate = new Date(today.getTime() - offset * 24 * 60 * 60 * 1000)
    const bucket = bucketDate.toISOString().slice(0, 10)
    points.push({
      timestamp: Math.floor(bucketDate.getTime() / 1000),
      value: counts.get(bucket) ?? 0,
    })
  }
  return points
}

export async function fetchThreatTimeseries() {
  const [hourlyRows, dailyRows] = await Promise.all([
    allDefault(HOURLY_SQL),
    allDefault(DAILY_SQL),
  ])

  return {
    requests24h: fillHourlyBuckets(hourlyRows),
    requests7d: fillDailyBuckets(dailyRows),
  }
}
