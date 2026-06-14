#!/usr/bin/env node
/**
 * Ships httpRequests from SQLite to ClickHouse OCI.
 * Runs as a continuous process.
 */
import path from 'path'
import { fileURLToPath } from 'url'
import fs from 'fs/promises'

import { getDb, all } from '../sqlite3.js'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const defaultDb = path.resolve(__dirname, '../../database.sqlite')
const cursorFile = path.resolve(__dirname, '../../.clickhouse_cursor')

const dbPath = process.env.QDBBACK_DB_PATH || defaultDb
const clickhouseUrl = process.env.CLICKHOUSE_URL || 'https://clickhouse.dnor.io'
const clickhouseUser = process.env.CLICKHOUSE_USER || 'default'
const clickhousePassword = process.env.CLICKHOUSE_PASSWORD || 'i4FtSOCFXu'

const sleep = (ms) => new Promise(r => setTimeout(r, ms))

const getCursor = async () => {
  try {
    const data = await fs.readFile(cursorFile, 'utf8')
    return parseInt(data.trim(), 10) || 0
  } catch (err) {
    return 0
  }
}

const saveCursor = async (id) => {
  await fs.writeFile(cursorFile, id.toString(), 'utf8')
}

const main = async () => {
  console.log(`Starting ClickHouse shipper to ${clickhouseUrl}`)
  const db = await getDb(dbPath)

  let cursor = await getCursor()
  console.log(`Resuming from id > ${cursor}`)

  while (true) {
    try {
      const rows = await all(db, 'SELECT * FROM httpRequests WHERE id > ? ORDER BY id ASC LIMIT 500', [cursor])
      
      if (rows.length > 0) {
        // Transform to ClickHouse JSONEachRow format
        const payload = rows.map(r => JSON.stringify({
          timestamp: r.timestamp.replace('T', ' ').replace('Z', ''),
          service: 'honeypot',
          ip: r.remoteIp || '-',
          method: r.method || '-',
          path: r.path || '-',
          status: (r.statusCode || 0).toString(),
          classification: r.classification || 'unknown',
          user_agent: r.userAgent || '-',
          time_elapsed: parseFloat(r.timeElapsed) || 0.0,
          country: r.country || ''
        })).join('\n')

        const response = await fetch(`${clickhouseUrl}/?query=INSERT+INTO+default.threat_intel_events+FORMAT+JSONEachRow`, {
          method: 'POST',
          headers: {
            'X-ClickHouse-User': clickhouseUser,
            'X-ClickHouse-Key': clickhousePassword,
          },
          body: payload
        })

        if (!response.ok) {
          const errText = await response.text()
          console.error(`ClickHouse insert failed: ${response.status} ${errText}`)
          await sleep(5000)
          continue
        }

        cursor = rows[rows.length - 1].id
        await saveCursor(cursor)
        console.log(`Shipped ${rows.length} events. Cursor updated to ${cursor}`)
      }
    } catch (err) {
      console.error('Error during shipping loop:', err.message)
    }

    await sleep(5000)
  }
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
