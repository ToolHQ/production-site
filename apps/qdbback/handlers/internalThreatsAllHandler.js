import { allDefault } from '../sqlite3.js'

export const internalThreatsAllHandler = async (req, res) => {
  try {
    const { searchParams } = new URL(req.url, `http://${req.headers.host || 'localhost'}`)
    const limit = parseInt(searchParams.get('limit')) || 50
    const offset = parseInt(searchParams.get('offset')) || 0

    const [{ total }] = await allDefault('SELECT COUNT(*) as total FROM httpRequests')
    
    const rows = await allDefault(`
      SELECT 
        id, 
        timestamp, 
        method, 
        path, 
        statusCode, 
        remoteHostname, 
        remoteIp,
        country, 
        classification 
      FROM httpRequests 
      ORDER BY timestamp DESC 
      LIMIT ? OFFSET ?
    `, [limit, offset])

    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ total, rows }))
  } catch (error) {
    res.writeHead(500, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ error: error.message }))
  }
}
