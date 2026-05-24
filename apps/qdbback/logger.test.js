import {
  beforeAll,
  describe,
  expect,
  jest,
  test,
} from '@jest/globals'

// eslint-disable-next-line no-unused-vars
const mockedLogFn = jest.fn((event, obj, severity) => {})

jest.mockModule('./sqlite3.js', () => ({
  log: mockedLogFn,
}))

/** @type {import('./logger.js')} */
let loggerModule

describe('logger.js', () => {
  beforeAll(async () => {
    loggerModule = await import('./logger.js')
  })

  describe('#log', () => {
    test('Should log single event', async () => {
      loggerModule.log('evento single')
      expect(mockedLogFn).toBeCalledWith('evento single', {}, 'info')
    })

    test('Should log info event properly', async () => {
      loggerModule.log('some event', { message: 'some important data' }, 'info')
      expect(mockedLogFn).toBeCalledWith('some event', { message: 'some important data' }, 'info')
    })
  })

  describe('logger', () => {
    test('#info: Should log info event', async () => {
      loggerModule.logger.info('some info event', { message: 'info data' })
      expect(mockedLogFn).toBeCalledWith('some info event', { message: 'info data' }, 'info')
    })

    test('#warn: Should log warn event', async () => {
      loggerModule.logger.warn('some warn event', { message: 'warn data' })
      expect(mockedLogFn).toBeCalledWith('some warn event', { message: 'warn data' }, 'warn')
    })

    test('#error: Should log error event', async () => {
      loggerModule.logger.error('some error event', { message: 'error data' })
      expect(mockedLogFn).toBeCalledWith('some error event', { message: 'error data' }, 'error')
    })
  })
})
