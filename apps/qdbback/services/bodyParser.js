/**
 * @param {import('http').IncomingMessage} req
 * @returns {Promise<Object|String>}
 */
export const parseBody = (req) => new Promise((resolve, reject) => {
  let body = ''
  req.on('data', (chunk) => {
    body += chunk.toString()
  })
  req.on('end', () => {
    if (req.headers['content-type'] === 'application/json' || req.headers['content-type'] === 'application/csp-report') {
      try {
        req.body = JSON.parse(body)
        resolve(req.body)
      } catch (err) {
        reject(err)
      }
    } else {
      req.body = body
      resolve(body)
    }
  })
})
