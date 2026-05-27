import {
  beforeAll,
  describe,
  expect,
  jest,
  test,
} from '@jest/globals'

const initMock = () => {
  const defaultReadFileResult = Buffer.from('')
  const defaultStatResult = { mtimeMs: 112231 }
  const readFileFn = jest.fn((_, callback) => {
    callback(null, defaultReadFileResult)
  })
  const statFn = jest.fn((_, callback) => {
    callback(null, defaultStatResult)
  })
  const createReadStreamFn = jest.fn()

  jest.mockModule('fs', () => ({
    readFile: readFileFn,
    stat: statFn,
    createReadStream: createReadStreamFn,
  }))
  jest.mockModule('../dir.js', () => ({
    __dirname: '/tmp/somedir/local/to/project/dir',
  }))

  const reloadMock = ({
    readFileResult = defaultReadFileResult,
    readFileError = null,
    statResult = defaultStatResult,
    statError = null,
  }) => {
    readFileFn.mockReset().mockImplementation((_, callback) => {
      callback(readFileError, readFileResult)
    })
    statFn.mockReset().mockImplementation((_, callback) => {
      callback(statError, statResult)
    })
    return {
      readFileFn,
      statFn,
      createReadStreamFn,
    }
  }
  return {
    reloadMock,
  }
}

const { reloadMock } = initMock()

/** @type {import('./fs.js')} */
let fs

describe('services/fs.js', () => {
  beforeAll(async () => {
    fs = await import('./fs.js')
  })

  describe('#readFileAsync', () => {
    test('Should return a file content from a buffer properly from a local path', async () => {
      const { readFileFn } = reloadMock({ readFileResult: Buffer.from('some content') })
      const result = await fs.readFileAsync('somefile.ext')
      expect(result).toBe('some content')
      expect(readFileFn).toBeCalledTimes(1)
      expect(readFileFn.mock.calls[0][0]).toBe('/tmp/somedir/local/to/project/dir/somefile.ext')
    })

    test('Should propagate an readFile error from a local path', async () => {
      const { readFileFn } = reloadMock({ readFileError: Error('ENOENT or another fs error') })
      try {
        await fs.readFileAsync('dont-exists.ext')
        throw Error('Should Propagate Error')
      } catch (err) {
        expect(err.message).toBe('ENOENT or another fs error')
        expect(readFileFn).toBeCalledTimes(1)
        expect(readFileFn.mock.calls[0][0]).toBe('/tmp/somedir/local/to/project/dir/dont-exists.ext')
      }
    })
  })

  describe('#fileLastModified', () => {
    test('Should return a stat.mtimeMs from a file from a local path', async () => {
      const { statFn } = reloadMock({ statResult: { mtimeMs: 12345 } })
      const result = await fs.fileLastModified('somefile.ext')
      expect(result).toBe(12345)
      expect(statFn).toBeCalledTimes(1)
      expect(statFn.mock.calls[0][0]).toBe('/tmp/somedir/local/to/project/dir/somefile.ext')
    })

    test('Should propagate an readFile error from a local path', async () => {
      const { statFn } = reloadMock({ statError: Error('ENOENT or another fs error') })
      try {
        await fs.fileLastModified('dont-exists.ext')
        throw Error('Should Propagate Error')
      } catch (err) {
        expect(err.message).toBe('ENOENT or another fs error')
        expect(statFn).toBeCalledTimes(1)
        expect(statFn.mock.calls[0][0]).toBe('/tmp/somedir/local/to/project/dir/dont-exists.ext')
      }
    })
  })

  describe('#createReadStream', () => {
    test('Should call createReadStream from a local path', async () => {
      const { createReadStreamFn } = reloadMock({})
      fs.createReadStream('somefile.ext')
      expect(createReadStreamFn).toBeCalledTimes(1)
      expect(createReadStreamFn.mock.calls[0][0]).toBe('/tmp/somedir/local/to/project/dir/somefile.ext')
    })
  })
})
