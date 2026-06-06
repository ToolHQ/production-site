import { allDefault } from '../sqlite3.js'

export const internalThreatsAllHandler = async (req, res) => {
  try {
    const { searchParams } = new URL(req.url, `http://${req.headers.host || 'localhost'}`)
    const limit = parseInt(searchParams.get('limit')) || 50
    const offset = parseInt(searchParams.get('offset')) || 0
    
    const method = searchParams.get('method')
    const path = searchParams.get('path')
    const ip = searchParams.get('ip')
    const classification = searchParams.get('classification')

    let whereClause = '1=1'
    const params = []

    if (method) {
      whereClause += ' AND method = ?'
      params.push(method)
    }
    if (path) {
      whereClause += ' AND path LIKE ?'
      params.push(`%${path}%`)
    }
    if (ip) {
      whereClause += ' AND remoteIp LIKE ?'
      params.push(`%${ip}%`)
    }
    if (classification) {
      if (classification === 'none') {
        whereClause += ' AND classification IS NULL'
      } else {
        whereClause += ' AND classification = ?'
        params.push(classification)
      }
    }

    const [{ total }] = await allDefault(`SELECT COUNT(*) as total FROM httpRequests WHERE ${whereClause}`, params)
    
    const rows = await allDefault(`
      SELECT 
        id, 
        timestamp, 
        method, 
        path, 
        timeElapsed,
        userAgent,
        statusCode, 
        remoteHostname, 
        remoteIp,
        country, 
        classification 
      FROM httpRequests 
      WHERE ${whereClause}
      ORDER BY timestamp DESC 
      LIMIT ? OFFSET ?
    `, [...params, limit, offset])

    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ total, rows }))
  } catch (error) {
    res.writeHead(500, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ error: error.message }))
  }
}
