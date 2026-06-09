/* eslint-disable max-classes-per-file */
import path from 'path'
import { Readable } from 'stream'
import sqlite3 from 'sqlite3'

import { __dirname } from './dir.js'

const MAX_LOGS = 10
let logsForSaving = []

const defaultFilename = path.resolve(__dirname, '../database.sqlite')

const cachedDBs = new Map()

/**
 * @returns {Promise<import('sqlite3').Database>}
 */
export const getDb = async (filename = defaultFilename) => {
  if (cachedDBs.has(filename)) {
    return cachedDBs.get(filename)
  }
  let dbDatabase
  await new Promise((resolve, reject) => {
    dbDatabase = new sqlite3.Database(filename, (err) => (err ? reject(err) : resolve()))
  })
  cachedDBs.set(filename, dbDatabase)
  return dbDatabase
}

/**
 * @param {import('sqlite3').Database} db
 */
export const close = (db) => new Promise((resolve, reject) => db.close((err) => (err ? reject(err) : resolve())))

/**
 * Close connection by name
 * @param {String} connName
 */
export const closeByName = async (connName) => {
  if (cachedDBs.has(connName)) {
    const db = cachedDBs.get(connName)
    await close(db)
    cachedDBs.delete(connName)
  }
}

/**
 * @param {import('sqlite3').Database} db
 * @param {String} sql
 * @param {String} sqlParams
 * @returns {Promise<any[]>}
 */
export const all = (db, sql, sqlParams = []) => new Promise((resolve, reject) => db
  .all(sql, sqlParams, (err, rows) => (err ? reject(err) : resolve(rows))))

/**
 * @param {import('sqlite3').Database} db
 * @param {String} sql
 * @param {String[]} sqlParams
 * @returns {Promise<import('sqlite3').RunResult>}
 */
export const run = (db, sql, sqlParams = []) => new Promise((resolve, reject) => db
  .run(sql, sqlParams, function returnRunResult(err) { return err ? reject(err) : resolve(this) }))

/**
 * @param {import('sqlite3').Database} db
 * @param {String} sql
 * @param {String[]} sqlParams
 */
export const get = (db, sql, sqlParams = []) => new Promise((resolve, reject) => db.get(sql, sqlParams, (err, row) => (err ? reject(err) : resolve(row))))

/**
 * Retorna um novo statement
 * @param {import('sqlite3').Database} db
 * @param {String} sql
 * @param {String[]} sqlParams
 * @returns {Promise<import('sqlite3').Statement>}
 */
export const prepare = (db, sql, sqlParams = []) => new Promise((resolve, reject) => db
  .prepare(sql, sqlParams, function returnStatement(err) { return err ? reject(err) : resolve(this) }))

/**
 * @param {import('sqlite3').Statement} statement
 * @param {String[]} sqlParams
 */
export const statementGet = (statement, sqlParams = []) => new Promise((resolve, reject) => statement.get(sqlParams, (err, row) => (err ? reject(err) : resolve(row))))

/**
 * @param {import('sqlite3').Statement} statement
 */
export const statementFinalize = (statement) => new Promise((resolve, reject) => statement.finalize((err) => (err ? reject(err) : resolve())))

/**
 * Uses default database, retrieves all rows, returns it
 * @param {String} sql
 * @param {String[]} sqlParams
 */
export const allDefault = async (sql, sqlParams = []) => {
  const db = await getDb()
  return all(db, sql, sqlParams)
}

/**
 * Uses default database, retrieves first row, returns it
 * @param {String} sql
 * @param {String[]} sqlParams
 */
export const getDefault = async (sql, sqlParams = []) => {
  const db = await getDb()
  return get(db, sql, sqlParams)
}

/**
 * Uses default database, execute query, returns result
 * @param {String} sql
 * @param {String[]} sqlParams
 */
export const runDefault = async (sql, sqlParams = []) => {
  const db = await getDb()
  return run(db, sql, sqlParams)
}

/**
 * Emits application logs, storing it to database always after 10 lines
 * @param {String} event
 * @param {Object} obj
 * @param {'info'|'error'} [severity]
 */
export const log = async (event, obj = {}, severity = 'info') => {
  const timestamp = new Date().toISOString()
  const logLine = JSON.stringify({
    severity, timestamp, event, ...obj,
  })
  if (severity === 'error') {
    process.stderr.write(`${logLine}\n`)
  } else {
    process.stdout.write(`${logLine}\n`)
  }
  logsForSaving.push([timestamp, severity, event, logLine])
  if (logsForSaving.length >= MAX_LOGS) {
    const logs = logsForSaving.slice(0, MAX_LOGS)
    logsForSaving = logsForSaving.slice(MAX_LOGS)
    await runDefault(`insert into applicationLogs (timestamp, severity, event, log) values ${'(?, ?, ?, ?), '
      .repeat(logs.length).slice(0, -2)}`, logs.flat(1))
  }
}

/**
 * Tenta iniciar banco e tables com logica create-if-not-exists, se der erro mata aplicacao.
 */
export const init = async () => {
  const hrTimeStart = process.hrtime()
  let db
  try {
    db = await getDb()
    await run(db, `create table if not exists httpRequests (
  id              INTEGER primary key,
  timestamp       TEXT not null,
  method          TEXT not null,
  path            TEXT not null,
  timeElapsed     NUMERIC not null,
  remoteIp        TEXT not null,
  remoteHostname  TEXT,
  statusCode      INTEGER,
  userAgent       TEXT,
  body            TEXT,
  headers         TEXT,
  country         TEXT,
  classification  TEXT
)`)
    await run(db, `create table if not exists applicationLogs (
  id              INTEGER primary key,
  timestamp       TEXT not null,
  severity        TEXT not null,
  event           TEXT not null,
  log             TEXT not null
)`)
    await run(db, `create table if not exists coolQueries (
  id              INTEGER primary key,
  query           TEXT not null,
  description     TEXT not null
)`)
    const hrTimeElapsed = process.hrtime(hrTimeStart)
    const timeElapsed = `${(hrTimeElapsed[0] * 1000 + hrTimeElapsed[1] / 1000000).toFixed(3)}ms`
    log('DB Initialized', {
      requestsReceived: (await all(db, 'select count(*) AS total FROM httpRequests'))[0].total,
      logsStored: (await all(db, 'select count(*) AS total FROM applicationLogs'))[0].total,
      timeElapsed,
    })
  } catch (err) {
    const hrTimeElapsed = process.hrtime(hrTimeStart)
    const timeElapsed = `${(hrTimeElapsed[0] * 1000 + hrTimeElapsed[1] / 1000000).toFixed(3)}ms`
    log('DB Init ERROR', {
      name: err.name, message: err.message, stack: err.stack, timeElapsed,
    }, 'error')
    if (db) {
      await close(db)
    }
    process.exit(1)
  }
}

class DBStream extends Readable {
  constructor(opt) {
    super(opt)
    this.stmt = opt.stmt
    this.count = opt.count
    this.total = 0
  }

  async _read() {
    const row = await statementGet(this.stmt)
    if (this.total === 0) {
      this.push(Buffer.from(`{"total":${this.count},"rows":[`, 'utf-8'))
    }
    if (row) {
      if (this.total === 0) {
        this.push(Buffer.from(JSON.stringify(row), 'utf-8'))
      } else {
        this.push(Buffer.from(`,${JSON.stringify(row)}`, 'utf-8'))
      }
      this.total += 1
    } else {
      await statementFinalize(this.stmt)
      this.push(Buffer.from(']}', 'utf-8'))
      this.push(null)
    }
  }
}

export const getStreamFromSQL = async (sql, sqlParams = [], count = 0) => {
  const db = await getDb()
  const stmt = await prepare(db, sql, sqlParams)
  log('DB Statement', { sql, sqlParams })
  return new DBStream({ stmt, count })
}

class DBStreamAnyRows extends Readable {
  constructor(opt) {
    super(opt)
    this.stmt = opt.stmt
    this.total = 0
  }

  async _read() {
    const row = await statementGet(this.stmt)
    if (this.total === 0) {
      this.push(Buffer.from('{"rows":[', 'utf-8'))
    }
    if (row) {
      if (this.total === 0) {
        this.push(Buffer.from(JSON.stringify(row), 'utf-8'))
      } else {
        this.push(Buffer.from(`,${JSON.stringify(row)}`, 'utf-8'))
      }
      this.total += 1
    } else {
      await statementFinalize(this.stmt)
      this.push(Buffer.from(`],"total":${this.total}}`, 'utf-8'))
      this.push(null)
    }
  }
}

export const getStreamFromAnySQL = async (sql, sqlParams = []) => {
  const db = await getDb()
  const stmt = await prepare(db, sql, sqlParams)
  log('DB Statement', { sql, sqlParams })
  return new DBStreamAnyRows({ stmt })
}

export default {
  getDb,
  close,
  all,
  get,
  prepare,
  statementGet,
  statementFinalize,
  allDefault,
  getDefault,
  runDefault,
  init,
  getStreamFromSQL,
  getStreamFromAnySQL,
}
