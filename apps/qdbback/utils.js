import { readFile, stat, createReadStream } from 'fs'
import path from 'path'
import { createHash } from 'crypto'
import { log } from './logger.js'

import { pipeline } from 'stream'

import { getEncoding, getEncoder } from './encoding.js'

import { mimeTypes, cacheConstants } from './constants.js'

const __dirname = decodeURIComponent(import.meta.url).split('file://').pop().split('/').slice(0, -1).join('/')

/**
 * @param {String} path
 * @returns {Promise<Buffer>}
 */
export const readFileAsync = path => new Promise((resolve, reject) => readFile(path, (err, data) => err ? reject(err) : resolve(data)))

/**
 * @param {String} path
 * @returns {Promise<Number>}
 */
const fileLastModified = path => new Promise((resolve, reject) => stat(path, (err, data) => err ? reject(err) : resolve(data.mtimeMs)))

const getSHA1 = str => createHash('sha1')
  .update(str)
  .digest('hex')

const sha1FromFiles = new Map()

const getFileInfo = ({ relativePath, cache = { time: cacheConstants.time.twoMinutes, policy: cacheConstants.policies.noCache }, encoding = false }) => {
  const absoluteFilePath = path.resolve(__dirname, relativePath)
  const extension = relativePath.split('.').pop()
  const contentType = mimeTypes[extension]
  return {
    absoluteFilePath,
    contentType,
    cacheControl: (cache.policy === cacheConstants.policies.noStore || cache.policy === cacheConstants.policies.noCache)
      ? cache.policy
      : cache.policy + ', max-age=' + cache.time.s,
    timeMillis: cache.time.ms,
    noEncoding: !encoding
  }
}

/**
 * Returns handler that reads from fixed file
 * @param {Object} options
 * @param {Object} [options.cache]
 * @param {Object} [options.cache.time]
 * @param {Number} options.cache.time.ms
 * @param {Number} options.cache.time.s
 * @param {String} [options.cache.policy]
 * @param {String} options.relativePath
 * @param {Boolean} [options.encoding=false]
 * @returns {import('./router').RequestListener}
 */
export const handleFileResponse = ({
  relativePath,
  cache = {
    time: cacheConstants.time.twoMinutes,
    policy: cacheConstants.policies.noCache
  },
  encoding = false
}) => {
  const {
    absoluteFilePath,
    contentType,
    cacheControl,
    timeMillis,
    noEncoding
  } = getFileInfo({ relativePath, cache, encoding })
  return async (req, res) => {
  // Cache controlling
    if (!sha1FromFiles.has(absoluteFilePath)) {
      sha1FromFiles.set(absoluteFilePath, getSHA1(String(await fileLastModified(absoluteFilePath))))
    }
    const lastModHash = sha1FromFiles.get(absoluteFilePath)
    res.setHeader('Content-Type', contentType)
    res.setHeader('Expires', new Date(Date.now() + timeMillis).toGMTString())
    res.setHeader('Cache-Control', cacheControl)
    res.setHeader('Vary', 'ETag')
    const ifNoneMatchValue = req.headers['if-none-match']
    res.setHeader('ETag', lastModHash)

    if (ifNoneMatchValue && ifNoneMatchValue === lastModHash) {
      res.statusCode = 304
      res.end()
    } else if (req.method === 'HEAD') {
      res.end()
    } else if (noEncoding) {
      createReadStream(absoluteFilePath).pipe(res)
    } else {
    // Encoding (gzip, br, etc)
      const encoderInfo = getEncoding(req.headers['accept-encoding'])
      if (!encoderInfo) {
        res.statusCode = 406
        res.setHeader('Content-Type', 'application/json')
        res.end(JSON.stringify({ error: 'Encoding Not Supported' }))
        return
      }
      res.setHeader('Content-Encoding', encoderInfo)

      // Stream results
      const fileStream = createReadStream(absoluteFilePath)
      if (encoderInfo !== 'identity') {
        pipeline(fileStream, getEncoder(encoderInfo), res, (err) => {
          if (err) {
            log('Encoding ERROR', err)
            res.end()
          }
        })
      } else {
        fileStream.pipe(res)
      }
    }
  }
}

export const parseBody = (req) => new Promise((resolve, reject) => {
  let body = ''
  req.on('data', chunk => {
    body += chunk.toString()
  })
  req.on('end', () => {
    req.body = body
    if (req.headers['content-type'] === 'application/json' || req.headers['content-type'] === 'application/csp-report') {
      try {
        resolve(JSON.parse(body))
      } catch (err) {
        reject(err)
      }
    } else {
      resolve(body)
    }
  })
})
