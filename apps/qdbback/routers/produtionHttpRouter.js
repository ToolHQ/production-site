/**
 * Useless router that always redirect to https
 * Used for production listener
 */

import { Router } from '../router.js'

export const getRouter = () => new Router((req, res) => {
  res.writeHead(301, {
    Location: `https://${req.headers.host}${req.url}`,
  })
  res.end()
})
