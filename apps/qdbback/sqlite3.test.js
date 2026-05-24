/* eslint-disable max-classes-per-file */
/* eslint-disable class-methods-use-this */

import {
  afterAll,
  beforeAll,
  describe,
  expect,
  jest,
  test,
} from '@jest/globals'

const FIXED_SYSTEM_TIME = '1994-04-03T15:00:00.000Z'

const initMock = () => {
  const MAX_LOGS = 10
  // sqlite3.Statement mocks
  const statementGetFn = jest.fn((sqlParams, callback) => {
    callback(null, null)
  })
  const statementFinalizeFn = jest.fn((callback) => {
    callback(null)
  })
  class Statement {
    get(sqlParams, callback) {
      statementGetFn(sqlParams, callback)
    }

    finalize(callback) {
      statementFinalizeFn(callback)
    }
  }

  // sqlite3.Database mocks
  const databaseConstructorFn = jest.fn((_, callback) => {
    callback(null)
  })
  const databaseCloseFn = jest.fn((callback) => {
    callback(null)
  })
  const databaseAllFn = jest.fn((sql, sqlParams, callback) => {
    callback(null, [])
  })
  const databaseGetFn = jest.fn((sql, sqlParams, callback) => {
    callback(null, [])
  })
  const defaultRunResult = {
    lastID: 123,
    changes: 0,
  }
  const databaseRunFn = jest.fn((sql, sqlParams, callback) => {
    callback.bind(defaultRunResult)(null)
  })
  const databasePrepareFn = jest.fn((sql, sqlParams, callback) => {
    callback.bind(new Statement())(null)
  })

  class Database {
    constructor(databasePath, callback) {
      databaseConstructorFn(databasePath, callback)
    }

    close(callback) {
      databaseCloseFn(callback)
    }

    all(sql, sqlParams, callback) {
      databaseAllFn(sql, sqlParams, callback)
    }

    get(sql, sqlParams, callback) {
      databaseGetFn(sql, sqlParams, callback)
    }

    run(sql, sqlParams, callback) {
      databaseRunFn(sql, sqlParams, callback)
    }

    prepare(sql, sqlParams, callback) {
      databasePrepareFn(sql, sqlParams, callback)
    }
  }
  jest.mockModule('sqlite3', () => ({
    default: {
      Database,
    },
  }))
  jest.mockModule('./dir.js', () => ({
    __dirname: '/tmp/somedir/',
  }))
  const reloadMock = ({
    constructorError = null,
    closeError = null,
    allResult = [],
    allResults = [],
    allError = null,
    getResult = [],
    getError = null,
    runResult = defaultRunResult,
    runError = null,
    prepareResult = new Statement(),
    prepareError = null,
    statementGetResults = [],
    statementFinalizeError = null,
  }) => {
    databaseConstructorFn.mockReset().mockImplementation((_, callback) => {
      callback(constructorError)
    })
    databaseCloseFn.mockReset().mockImplementation((callback) => {
      callback(closeError)
    })
    databaseAllFn.mockReset().mockImplementation((sql, sqlParams, callback) => {
      if (allError) {
        callback(allError)
      } else {
        callback(allError, allResults.length ? allResults.shift() : allResult)
      }
    })
    databaseGetFn.mockReset().mockImplementation((sql, sqlParams, callback) => {
      if (getError) {
        callback(getError)
      } else {
        callback(getError, getResult)
      }
    })
    databaseRunFn.mockReset().mockImplementation((sql, sqlParams, callback) => {
      callback.bind(runResult)(runError)
    })
    databasePrepareFn.mockReset().mockImplementation((sql, sqlParams, callback) => {
      callback.bind(prepareResult)(prepareError)
    })
    statementGetFn.mockReset().mockImplementation((sqlParams, callback) => {
      if (statementGetResults.length) {
        const result = statementGetResults.shift()
        if (result instanceof Error) {
          callback(result)
        } else {
          callback(null, result)
        }
      } else {
        callback(null, null)
      }
    })
    statementFinalizeFn.mockReset().mockImplementation((callback) => {
      callback(statementFinalizeError)
    })
    return {
      databaseConstructorFn,
      databaseCloseFn,
      databaseAllFn,
      databaseRunFn,
      databaseGetFn,
      Statement,
      databasePrepareFn,
      statementGetFn,
      statementFinalizeFn,
      MAX_LOGS,
    }
  }
  return {
    reloadMock,
  }
}

const { reloadMock } = initMock()

/** @type {import('./sqlite3.js')} */
let sqlite3

describe('sqlite3.js', () => {
  beforeAll(async () => {
    sqlite3 = await import('./sqlite3.js')
    jest.useFakeTimers()
    jest.setSystemTime(Date.parse(FIXED_SYSTEM_TIME))
  })

  afterAll(() => {
    jest.useRealTimers()
  })

  describe('#getDb', () => {
    test('Should return a default connection', async () => {
      const { databaseConstructorFn } = reloadMock({ constructorError: null })
      const db = await sqlite3.getDb()
      const sameDb = await sqlite3.getDb()
      expect(db).toBe(sameDb)
      expect(databaseConstructorFn.mock.calls[0][0]).toBe('/tmp/database.sqlite')
    })

    test('Should return a db conn instance properly with cache for same connections', async () => {
      const { databaseConstructorFn } = reloadMock({ constructorError: null })
      const db = await sqlite3.getDb('conn1FileName')
      const sameDb = await sqlite3.getDb('conn1FileName')
      expect(db).toBe(sameDb)
      expect(databaseConstructorFn).toBeCalledTimes(1)
      const otherDb = await sqlite3.getDb('conn2FileName')
      expect(databaseConstructorFn).toBeCalledTimes(2)
      expect(db).not.toBe(otherDb)
    })

    test('Should propagate sqlite3 initialization Error properly', async () => {
      const { databaseConstructorFn } = reloadMock({ constructorError: Error('new sqlite3.Database() initialization Error') })
      try {
        await sqlite3.getDb('notFoundFileName')
        throw Error('Should Propagate Error')
      } catch (err) {
        expect(err).toHaveProperty('message', 'new sqlite3.Database() initialization Error')
        expect(databaseConstructorFn).toBeCalledTimes(1)
      }
    })
  })

  describe('#close', () => {
    test('Should call database.close when close is called', async () => {
      const { databaseCloseFn } = reloadMock({})
      const db = await sqlite3.getDb()
      await sqlite3.close(db)
      expect(databaseCloseFn).toBeCalledTimes(1)
    })

    test('Should propagate database.close Error properly', async () => {
      const { databaseCloseFn } = reloadMock({ closeError: Error('sqlite3.Database.close() Error') })
      try {
        const db = await sqlite3.getDb()
        await sqlite3.close(db)
        throw Error('Should Propagate Error')
      } catch (err) {
        expect(err).toHaveProperty('message', 'sqlite3.Database.close() Error')
        expect(databaseCloseFn).toBeCalledTimes(1)
      }
    })
  })

  describe('#all', () => {
    test('Should call database.all when #all is called', async () => {
      const allResult = [
        {
          name: 'Bob',
        },
        {
          name: 'Alice',
        },
      ]
      const { databaseAllFn } = reloadMock({ allResult })
      const db = await sqlite3.getDb()
      const result = await sqlite3.all(db, 'SELECT name FROM TB_USERS')
      expect(databaseAllFn).toBeCalledTimes(1)
      expect(databaseAllFn.mock.calls[0][0]).toEqual('SELECT name FROM TB_USERS')
      expect(result).toStrictEqual(allResult)
    })

    test('Should propagate database.all Error properly', async () => {
      const { databaseAllFn } = reloadMock({ allError: Error('sqlite3.Database.all() Error') })
      try {
        const db = await sqlite3.getDb()
        await sqlite3.all(db, 'SELECT ? FROM DUAL', [1])
        throw Error('Should Propagate Error')
      } catch (err) {
        expect(err).toHaveProperty('message', 'sqlite3.Database.all() Error')
        expect(databaseAllFn).toBeCalledTimes(1)
      }
    })
  })

  describe('#get', () => {
    test('Should call database.get when #get is called', async () => {
      const getResult = [
        {
          name: 'Bob',
        },
        {
          name: 'Alice',
        },
      ]
      const { databaseGetFn } = reloadMock({ getResult })
      const db = await sqlite3.getDb()
      const result = await sqlite3.get(db, 'SELECT name FROM TB_USERS')
      expect(databaseGetFn).toBeCalledTimes(1)
      expect(databaseGetFn.mock.calls[0][0]).toEqual('SELECT name FROM TB_USERS')
      expect(result).toStrictEqual(getResult)
    })

    test('Should propagate database.get Error properly', async () => {
      const { databaseGetFn } = reloadMock({ getError: Error('sqlite3.Database.get() Error') })
      try {
        const db = await sqlite3.getDb()
        await sqlite3.get(db, 'SELECT ? FROM DUAL', [1])
        throw Error('Should Propagate Error')
      } catch (err) {
        expect(err).toHaveProperty('message', 'sqlite3.Database.get() Error')
        expect(databaseGetFn).toBeCalledTimes(1)
      }
    })
  })

  describe('#allDefault', () => {
    test('Should call database.all when #allDefault is called', async () => {
      const allResult = []
      const { databaseAllFn } = reloadMock({ allResult })
      const result = await sqlite3.allDefault("UPDATE TB_USERS SET name='Bob' WHERE name='bob'")
      expect(databaseAllFn).toBeCalledTimes(1)
      expect(databaseAllFn.mock.calls[0][0]).toEqual("UPDATE TB_USERS SET name='Bob' WHERE name='bob'")
      expect(result).toStrictEqual(allResult)
    })

    test('Should propagate database.all Error properly', async () => {
      const { databaseAllFn } = reloadMock({ allError: Error('sqlite3.Database.all() Error') })
      try {
        await sqlite3.allDefault('UPDATE ? FROM DUAL', [1])
        throw Error('Should Propagate Error')
      } catch (err) {
        expect(err).toHaveProperty('message', 'sqlite3.Database.all() Error')
        expect(databaseAllFn).toBeCalledTimes(1)
      }
    })
  })

  describe('#getDefault', () => {
    test('Should call database.get when #getDefault is called', async () => {
      const getResult = [
        {
          name: 'Bob',
        },
        {
          name: 'Alice',
        },
      ]
      const { databaseGetFn } = reloadMock({ getResult })
      const result = await sqlite3.getDefault('SELECT name FROM TB_USERS')
      expect(databaseGetFn).toBeCalledTimes(1)
      expect(databaseGetFn.mock.calls[0][0]).toEqual('SELECT name FROM TB_USERS')
      expect(result).toStrictEqual(getResult)
    })

    test('Should propagate database.get Error properly', async () => {
      const { databaseGetFn } = reloadMock({ getError: Error('sqlite3.Database.get() Error') })
      try {
        await sqlite3.getDefault('UPDATE ? FROM DUAL', [1])
        throw Error('Should Propagate Error')
      } catch (err) {
        expect(err).toHaveProperty('message', 'sqlite3.Database.get() Error')
        expect(databaseGetFn).toBeCalledTimes(1)
      }
    })
  })

  describe('#runDefault', () => {
    test('Should call database.run when #runDefault is called', async () => {
      const runResult = {
        lastID: 123,
        changes: 1,
      }
      const { databaseRunFn } = reloadMock({ runResult })
      const result = await sqlite3.runDefault("UPDATE TB_USERS SET name='Bob' WHERE name='bob'")
      expect(databaseRunFn).toBeCalledTimes(1)
      expect(databaseRunFn.mock.calls[0][0]).toEqual("UPDATE TB_USERS SET name='Bob' WHERE name='bob'")
      expect(result).toStrictEqual(runResult)
    })

    test('Should propagate database.run Error properly', async () => {
      const { databaseRunFn } = reloadMock({ runError: Error('sqlite3.Database.run() Error') })
      try {
        await sqlite3.runDefault('UPDATE ? FROM DUAL', [1])
        throw Error('Should Propagate Error')
      } catch (err) {
        expect(err).toHaveProperty('message', 'sqlite3.Database.run() Error')
        expect(databaseRunFn).toBeCalledTimes(1)
      }
    })
  })

  describe('#prepare', () => {
    test('Should call database.prepare when #prepare is called', async () => {
      const { Statement, databasePrepareFn } = reloadMock({})
      const db = await sqlite3.getDb()
      const result = await sqlite3.prepare(db, 'SELECT name FROM TB_USERS')
      expect(databasePrepareFn).toBeCalledTimes(1)
      expect(databasePrepareFn.mock.calls[0][0]).toEqual('SELECT name FROM TB_USERS')
      expect(result).toBeInstanceOf(Statement)
    })

    test('Should propagate database.prepare Error properly', async () => {
      const { databasePrepareFn } = reloadMock({ prepareError: Error('sqlite3.Database.prepare() Error') })
      try {
        const db = await sqlite3.getDb()
        await sqlite3.prepare(db, 'SELECT ? FROM DUAL', [1])
        throw Error('Should Propagate Error')
      } catch (err) {
        expect(err).toHaveProperty('message', 'sqlite3.Database.prepare() Error')
        expect(databasePrepareFn).toBeCalledTimes(1)
      }
    })
  })

  describe('#statementGet', () => {
    test('Should call statement.get when #statementGet is called', async () => {
      const { Statement } = reloadMock({ statementGetResults: [{ name: 'Bob' }, { name: 'Alice' }] })
      const db = await sqlite3.getDb()
      const stmt = await sqlite3.prepare(db, 'SELECT name FROM TB_USERS')
      const firstResult = await sqlite3.statementGet(stmt)
      const secondResult = await sqlite3.statementGet(stmt)
      expect(stmt).toBeInstanceOf(Statement)
      expect(firstResult).toStrictEqual({ name: 'Bob' })
      expect(secondResult).toStrictEqual({ name: 'Alice' })
    })

    test('Should propagate statement.get error properly when called', async () => {
      const { Statement } = reloadMock({ statementGetResults: [{ name: 'Bob' }, Error('sqlite3.Statement.prepare() Error')] })
      let firstResult
      try {
        const db = await sqlite3.getDb()
        const stmt = await sqlite3.prepare(db, 'SELECT name FROM TB_USERS')
        expect(stmt).toBeInstanceOf(Statement)
        firstResult = await sqlite3.statementGet(stmt)
        await sqlite3.statementGet(stmt)
        throw Error('Should Propagate Error')
      } catch (err) {
        expect(err).toHaveProperty('message', 'sqlite3.Statement.prepare() Error')
        expect(firstResult).toStrictEqual({ name: 'Bob' })
      }
    })
  })

  describe('#statementFinalize', () => {
    test('Should call statement.finalize when statementFinalize is called', async () => {
      const { statementFinalizeFn } = reloadMock({})
      const db = await sqlite3.getDb()
      const stmt = await sqlite3.prepare(db, 'SELECT name FROM TB_USERS')
      await sqlite3.statementFinalize(stmt)
      expect(statementFinalizeFn).toBeCalledTimes(1)
    })

    test('Should propagate statement.finalize Error properly', async () => {
      const { statementFinalizeFn } = reloadMock({ statementFinalizeError: Error('sqlite3.Statement.finalize() Error') })
      try {
        const db = await sqlite3.getDb()
        const stmt = await sqlite3.prepare(db, 'SELECT name FROM TB_USERS')
        await sqlite3.close(db)
        await sqlite3.statementFinalize(stmt)
        throw Error('Should Propagate Error')
      } catch (err) {
        expect(err).toHaveProperty('message', 'sqlite3.Statement.finalize() Error')
        expect(statementFinalizeFn).toBeCalledTimes(1)
      }
    })
  })

  describe('#log', () => {
    test('Should log call process.stdout and dispatch logs lines with db.run', async () => {
      const mockProcessStdoutWrite = jest.spyOn(process.stdout, 'write').mockImplementation(() => {})
      const mockProcessStderrWrite = jest.spyOn(process.stderr, 'write').mockImplementation(() => {})
      const { databaseRunFn, MAX_LOGS } = reloadMock({})
      const logOperations = []
      for (let i = 0; i < MAX_LOGS; i++) {
        if (i % 2 === 0) {
          logOperations.push(sqlite3.log('log test event', { message: 'something important', i }))
        } else if (i % 3 === 0) {
          logOperations.push(sqlite3.log('log test event empty'))
        } else {
          logOperations.push(sqlite3.log('log test event', { message: 'something important, but with error', i }, 'error'))
        }
      }

      const logInfo = (i) => `${JSON.stringify({
        severity: 'info',
        timestamp: FIXED_SYSTEM_TIME,
        event: 'log test event',
        message: 'something important',
        i,
      })}\n`
      const logError = (i) => `${JSON.stringify({
        severity: 'error',
        timestamp: FIXED_SYSTEM_TIME,
        event: 'log test event',
        message: 'something important, but with error',
        i,
      })}\n`
      const logEmpty = `${JSON.stringify({
        severity: 'info',
        timestamp: FIXED_SYSTEM_TIME,
        event: 'log test event empty',
      })}\n`

      await Promise.all(logOperations)
      expect(databaseRunFn).toHaveBeenCalled()
      expect(databaseRunFn.mock.calls[0][0]).toEqual(`insert into applicationLogs (timestamp, severity, event, log) values ${'(?, ?, ?, ?), '.repeat(MAX_LOGS).slice(0, -2)}`)
      expect(mockProcessStdoutWrite.mock.calls).toEqual([
        [logInfo(0)],
        [logInfo(2)],
        [logEmpty],
        [logInfo(4)],
        [logInfo(6)],
        [logInfo(8)],
        [logEmpty],
      ])
      expect(mockProcessStderrWrite.mock.calls).toEqual([
        [logError(1)],
        [logError(5)],
        [logError(7)],
      ])
      mockProcessStdoutWrite.mockRestore()
      mockProcessStderrWrite.mockRestore()
    })
  })

  describe('#init', () => {
    test('Should init database properly', async () => {
      const mockProcessStdoutWrite = jest.spyOn(process.stdout, 'write').mockImplementation(() => {})
      const { databaseRunFn, databaseAllFn } = reloadMock({ allResults: [[{ total: 1 }], [{ total: 3 }]] })
      await sqlite3.init()
      expect(databaseRunFn).toHaveBeenCalledTimes(3)
      expect(databaseRunFn.mock.calls[0][0]).toMatch(/create table if not exists httpRequests/)
      expect(databaseRunFn.mock.calls[1][0]).toMatch(/create table if not exists applicationLogs/)
      expect(databaseRunFn.mock.calls[2][0]).toMatch(/create table if not exists coolQueries/)
      expect(databaseAllFn).toHaveBeenCalledTimes(2)
      expect(databaseAllFn.mock.calls[0][0]).toBe('select count(*) AS total FROM httpRequests')
      expect(databaseAllFn.mock.calls[1][0]).toBe('select count(*) AS total FROM applicationLogs')
      mockProcessStdoutWrite.mockRestore()
    })

    test('Should fail to init database and gracefully close database and application', async () => {
      const mockProcessStderrWrite = jest.spyOn(process.stderr, 'write').mockImplementation(() => {})
      const mockExit = jest.spyOn(process, 'exit').mockImplementation(() => {})
      const { databaseRunFn, databaseCloseFn } = reloadMock({ runError: Error('Some database error') })
      await sqlite3.init()
      expect(databaseRunFn).toHaveBeenCalledTimes(1)
      expect(databaseCloseFn).toHaveBeenCalledTimes(1)
      expect(mockExit).toHaveBeenCalledWith(1)
      mockExit.mockRestore()
      mockProcessStderrWrite.mockRestore()
    })

    test('Should fail to init database on getDb and gracefully exit application', async () => {
      const mockProcessStderrWrite = jest.spyOn(process.stderr, 'write').mockImplementation(() => {})
      const mockExit = jest.spyOn(process, 'exit').mockImplementation(() => {})
      await sqlite3.closeByName('/tmp/database.sqlite')
      await sqlite3.closeByName('/tmp/i-dont-exists')
      const { databaseRunFn, databaseCloseFn } = reloadMock({ constructorError: Error('Some constructor error') })
      await sqlite3.init()
      expect(databaseRunFn).toHaveBeenCalledTimes(0)
      expect(databaseCloseFn).toHaveBeenCalledTimes(0)
      expect(mockExit).toHaveBeenCalledWith(1)
      mockExit.mockRestore()
      mockProcessStderrWrite.mockRestore()
    })
  })

  describe('#getStreamFromSQL', () => {
    test('Should be used without errors for paginated results with pre-computed total', async () => {
      const mockProcessStdoutWrite = jest.spyOn(process.stdout, 'write').mockImplementation(() => {})
      reloadMock({ statementGetResults: [{ name: 'Bob' }, { name: 'Alice' }] })
      const stream = await sqlite3.getStreamFromSQL('SELECT name FROM TB_USERS', { $offset: 0, $limit: 2 }, 100)
      const result = await new Promise((resolve) => {
        let data = ''
        stream.on('data', (chunk) => {
          data += chunk
        })

        stream.on('end', () => {
          resolve(data)
        })
      })
      expect(result).toBe(JSON.stringify({ total: 100, rows: [{ name: 'Bob' }, { name: 'Alice' }] }))
      mockProcessStdoutWrite.mockRestore()
    })

    test('Should be used without errors for paginated results with pre-computed total 0 when not provided', async () => {
      const mockProcessStdoutWrite = jest.spyOn(process.stdout, 'write').mockImplementation(() => {})
      reloadMock({ statementGetResults: [{ name: 'Bob' }, { name: 'Alice' }] })
      const stream = await sqlite3.getStreamFromSQL('SELECT name FROM TB_USERS')
      const result = await new Promise((resolve) => {
        let data = ''
        stream.on('data', (chunk) => {
          data += chunk
        })

        stream.on('end', () => {
          resolve(data)
        })
      })
      expect(result).toBe(JSON.stringify({ total: 0, rows: [{ name: 'Bob' }, { name: 'Alice' }] }))
      mockProcessStdoutWrite.mockRestore()
    })
  })

  describe('#getStreamFromAnySQL', () => {
    test('Should be used without errors for non-paginated results without pre-computed total', async () => {
      const mockProcessStdoutWrite = jest.spyOn(process.stdout, 'write').mockImplementation(() => {})
      reloadMock({ statementGetResults: [{ name: 'Bob' }, { name: 'Alice' }, { name: 'Charles' }] })
      const stream = await sqlite3.getStreamFromAnySQL('SELECT name FROM TB_USERS')
      const result = await new Promise((resolve) => {
        let data = ''
        stream.on('data', (chunk) => {
          data += chunk
        })

        stream.on('end', () => {
          resolve(data)
        })
      })
      expect(result).toBe(JSON.stringify({ rows: [{ name: 'Bob' }, { name: 'Alice' }, { name: 'Charles' }], total: 3 }))
      mockProcessStdoutWrite.mockRestore()
    })
  })
})
