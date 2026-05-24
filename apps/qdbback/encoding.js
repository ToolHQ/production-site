import zlib from 'zlib'
import { PassThrough } from 'stream'

const supportedEncodings = [
  'gzip',
  'identity',
  'br',
  'deflate'
]

/**
 * @param {String} acceptEncodingStr
 * @example parseAcceptEncodingHeader('deflate, gzip;q=1.0, *;q=0.5 ')
 * => [{ type: 'deflate', qValue: 1 }, { type: 'gzip', qValue: 1 }, { type: '*', qValue: 0.5 }]
 */
export const parseAcceptEncodingHeader = (acceptEncodingStr = '') =>
  acceptEncodingStr
    .split(',')
    .map(enc => {
      const [type, qValueRaw = 'q=1.0'] = enc.trim().split(';')
      return {
        type: type.trim() || '*',
        qValue: parseFloat(qValueRaw.split('=')[1])
      }
    })
    .sort((a, b) => b.qValue - a.qValue)

export const getEncoding = acceptEncodingStr => {
  if (!acceptEncodingStr || acceptEncodingStr.trim().length === 0) {
    return 'identity'
  }
  const encodings = parseAcceptEncodingHeader(acceptEncodingStr)
  let acceptOthers = true
  const forbiddenEncodings = []
  const candidates = []
  for (const { type, qValue } of encodings) {
    if (type === '*') {
      if (qValue === 0) {
        acceptOthers = false
      }
    } else {
      if (supportedEncodings.includes(type)) {
        if (qValue > 0) {
          candidates.push(type)
        } else {
          forbiddenEncodings.push(type)
        }
      }
    }
  }
  if (candidates.length) return candidates[0]
  if (acceptOthers) {
    const otherEncondings = supportedEncodings.filter(t => !forbiddenEncodings.includes(t))
    return otherEncondings.length ? otherEncondings[0] : null
  }
  return null
}

export const getEncoder = encoderInfo => {
  switch (encoderInfo) {
    case 'gzip': return zlib.createGzip()
    case 'deflate': return zlib.createDeflate()
    case 'br': return zlib.createBrotliCompress()
    case 'identity': return new PassThrough()
    default: return null
  }
}
