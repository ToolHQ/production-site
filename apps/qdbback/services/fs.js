import { readFile, stat, createReadStream as createReadStreamFS } from 'fs'
import path from 'path'

import { __dirname } from '../dir.js'

/**
 * @param {String} filePath
 * @returns {Promise<String>}
 */
export const readFileAsync = (filePath) => new Promise((resolve, reject) => readFile(
  path.resolve(__dirname, filePath),
  (err, data) => (err ? reject(err) : resolve(data.toString())),
))

/**
 * @param {String} filePath
 * @returns {Promise<Number>}
 */
export const fileLastModified = (filePath) => new Promise((resolve, reject) => stat(path.resolve(__dirname, filePath), (err, data) => (err ? reject(err) : resolve(data.mtimeMs))))

/**
 * @param {String} filePath
 */
export const createReadStream = (filePath) => createReadStreamFS(path.resolve(__dirname, filePath))
