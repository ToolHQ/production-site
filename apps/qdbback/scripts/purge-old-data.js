#!/usr/bin/env node
/**
 * Purge old rows from qdbback SQLite — run via cron/systemd on EC2.
 *
 * Env:
 *   QDBBACK_DB_PATH          (default: ../database.sqlite from server/)
 *   QDBBACK_LOGS_KEEP_DAYS   (default: 30)
 *   QDBBACK_REQUESTS_KEEP_DAYS (default: 0 = keep all requests)
 */
import path from 'path'
import { fileURLToPath } from 'url'

import { getDb, close, run, all } from '../sqlite3.js'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const defaultDb = path.resolve(__dirname, '../../database.sqlite')

const dbPath = process.env.QDBBACK_DB_PATH || defaultDb
const logsKeepDays = Number(process.env.QDBBACK_LOGS_KEEP_DAYS || 30)
const requestsKeepDays = Number(process.env.QDBBACK_REQUESTS_KEEP_DAYS || 0)

const cutoffIso = (days) => new Date(Date.now() - days * 86400000).toISOString()

const main = async () => {
  const db = await getDb(dbPath)
  const beforeLogs = (await all(db, 'SELECT COUNT(*) AS total FROM applicationLogs'))[0].total
  const beforeReq = (await all(db, 'SELECT COUNT(*) AS total FROM httpRequests'))[0].total

  if (logsKeepDays > 0) {
    await run(db, 'DELETE FROM applicationLogs WHERE timestamp < ?', [cutoffIso(logsKeepDays)])
  }

  if (requestsKeepDays > 0) {
    await run(db, 'DELETE FROM httpRequests WHERE timestamp < ?', [cutoffIso(requestsKeepDays)])
  }

  await run(db, 'VACUUM')

  const afterLogs = (await all(db, 'SELECT COUNT(*) AS total FROM applicationLogs'))[0].total
  const afterReq = (await all(db, 'SELECT COUNT(*) AS total FROM httpRequests'))[0].total

  console.log(JSON.stringify({
    dbPath,
    logsKeepDays,
    requestsKeepDays,
    applicationLogs: { before: beforeLogs, after: afterLogs, removed: beforeLogs - afterLogs },
    httpRequests: { before: beforeReq, after: afterReq, removed: beforeReq - afterReq },
  }))

  await close(db)
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
