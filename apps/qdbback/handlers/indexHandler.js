import { mimeTypes } from '../constants.js'

/**
 * @type {import('../router').RequestListener}
 */
export const indexHandler = (_, res) => {
  res.setHeader('Content-Type', mimeTypes.html)
  res
    .writeHead(200)
    .write('<html><h1>Aprecie este maravilhoso pudim</h1><img src="pudim.png"></html>')
  res.end()
}
