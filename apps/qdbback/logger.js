import { log as logWithDB } from './sqlite3.js'

export const log = (event, obj = {}, severity = 'info') => logWithDB(event, obj, severity)

export const logger = {
  info: (event, obj) => log(event, obj, 'info'),
  warn: (event, obj) => log(event, obj, 'warn'),
  error: (event, obj) => log(event, obj, 'error'),
}
