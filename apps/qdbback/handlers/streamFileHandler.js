import { createHash } from 'crypto'
import { pipeline } from 'stream'

import { logger } from '../logger.js'
import { mimeTypes, cacheConstants } from '../constants.js'
import { getEncoding, getEncoder } from '../services/encoding.js'
import { createReadStream, fileLastModified } from '../services/fs.js'

const getSHA1 = (str) => createHash('sha1')
  .update(str)
  .digest('hex')

const sha1FromFiles = new Map()

const getFileInfo = ({ relativePath, cache = { time: cacheConstants.time.twoMinutes, policy: cacheConstants.policies.noCache }, encoding = false }) => {
  const extension = relativePath.split('.').pop()
  // eslint-disable-next-line security/detect-object-injection
  const contentType = Object.prototype.hasOwnProperty.call(mimeTypes, extension) ? mimeTypes[extension] : null
  return {
    contentType,
    cacheControl: (cache.policy === cacheConstants.policies.noStore || cache.policy === cacheConstants.policies.noCache)
      ? cache.policy
      : `${cache.policy}, max-age=${cache.time.s}`,
    timeMillis: cache.time.ms,
    noEncoding: !encoding,
  }
}

/**
 * Returns handler that reads from local file and stream it with requested enconding
 * @param {Object} options
 * @param {Object} [options.cache]
 * @param {Object} [options.cache.time]
 * @param {Number} options.cache.time.ms
 * @param {Number} options.cache.time.s
 * @param {String} [options.cache.policy]
 * @param {String} options.relativePath
 * @param {Boolean} [options.encoding=false]
 * @returns {import('../router').RequestListener}
 */
export const handleFileResponse = ({
  relativePath,
  cache = {
    time: cacheConstants.time.twoMinutes,
    policy: cacheConstants.policies.noCache,
  },
  encoding = false,
}) => {
  const {
    contentType,
    cacheControl,
    timeMillis,
    noEncoding,
  } = getFileInfo({ relativePath, cache, encoding })
  return async (req, res) => {
  // Cache controlling
    if (!sha1FromFiles.has(relativePath)) {
      sha1FromFiles.set(relativePath, getSHA1(String(await fileLastModified(relativePath))))
    }
    const lastModHash = sha1FromFiles.get(relativePath)
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
      createReadStream(relativePath).pipe(res)
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
      const fileStream = createReadStream(relativePath)
      if (encoderInfo !== 'identity') {
        pipeline(fileStream, getEncoder(encoderInfo), res, (err) => {
          if (err) {
            logger.error('Encoding ERROR', { cause: err.message, name: err.name, stack: err.stack })
            res.end()
          }
        })
      } else {
        fileStream.pipe(res)
      }
    }
  }
}
