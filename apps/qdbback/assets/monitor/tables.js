/* eslint-disable class-methods-use-this */
/* eslint-disable max-classes-per-file */
import { DataTable } from './components/DataTable.js'
import { SimpleDataTable } from './components/SimpleDataTable.js'
import { defaultPartRequests, defaultPartLogs, defaultOrderBysStr } from './urlState.js'

const orderBysObjToStr = (orderBys) => Object.entries(orderBys).map(([key, order]) => (order === 'descending' ? `desc(${key})` : `asc(${key})`)).join(',')

const ALLOWED_SORT_COLUMNS = new Set([
  'id', 'timestamp', 'method', 'path', 'timeElapsed',
  'remoteHostname', 'statusCode', 'severity', 'event', 'log'
])

/**
 * @param {String} orderBys
 */
const orderBysStrToObj = (orderBys) => {
  if (!orderBys) return {}
  return orderBys.split(',').reduce((ordersByObj, orderBy) => {
    if (orderBy.startsWith('desc(')) {
      const key = orderBy.slice(5, -1)
      if (!ALLOWED_SORT_COLUMNS.has(key)) return ordersByObj
      // eslint-disable-next-line no-param-reassign
      ordersByObj[key] = 'descending'
    } else {
      const key = orderBy.slice(4, -1)
      if (!ALLOWED_SORT_COLUMNS.has(key)) return ordersByObj
      // eslint-disable-next-line no-param-reassign
      ordersByObj[key] = 'acending'
    }
    return ordersByObj
  }, {})
}

class MonitorRequestsDataTable extends DataTable {
  async fetchData() {
    let sortBy = orderBysObjToStr(this.orderBys)
    if (sortBy) {
      sortBy = `&sort_by=${sortBy}`
    }
    const response = await fetch(`/api/monitor/requests?part=${this.columns.join(',')}&limit=${this.limit}&offset=${this.offset}${sortBy}`)
    return response.json()
  }
}

class LogsDataTable extends DataTable {
  async fetchData() {
    let sortBy = orderBysObjToStr(this.orderBys)
    if (sortBy) {
      sortBy = `&sort_by=${sortBy}`
    }
    const { total, rows } = await (await fetch(`/api/monitor/logs?part=${this.columns.join(',')}&limit=${this.limit}&offset=${this.offset}${sortBy}`)).json()
    return { total, rows: rows.map((r) => ({ ...r, log: JSON.stringify(JSON.parse(r.log), null, 2) })) }
  }
}

class SqlResultDataTable extends SimpleDataTable {
  async fetchData(inputText) {
    const result = await fetch('/api/monitor/sql', {
      method: 'POST',
      headers: {
        'Content-Type': 'text/plain',
      },
      body: inputText,
    })
    if (result.ok) {
      const { total, rows } = await result.json()
      return { total, rows }
    }
    const errResponse = await result.json()
    // eslint-disable-next-line no-console
    console.error(errResponse)
    throw Error(errResponse.message || errResponse)
  }
}

export const initSqlResultTable = ({ html, fatherElement }) => new SqlResultDataTable({
  html,
  fatherElement,
  tableName: 'SQL Result Table',
})

export const initRequestsTable = ({
  html, fatherElement, part, limit, offset, orderBysStr, requestsTab, locale,
}) => new MonitorRequestsDataTable({
  html,
  fatherElement,
  tableName: 'HTTP Requests Table',
  labelRowsPerPage: locale === 'pt-BR' ? 'Linhas por página' : 'Lines per page',
  columns: (requestsTab && part.split(',')) || defaultPartRequests.split(','), // Columns to display
  columnsHeaders: { // Header mapping
    id: 'Id',
    timestamp: 'Timestamp',
    method: locale === 'pt-BR' ? 'Método' : 'Method',
    timeElapsed: locale === 'pt-BR' ? 'Tempo Total' : 'Time Elapsed',
    remoteHostname: 'Remote Hostname',
    statusCode: 'Status Code',
  },
  orderBys: orderBysStrToObj((requestsTab && orderBysStr) || defaultOrderBysStr),
  defaultOrderBysStr,
  columnTypes: {
    statusCode: 'numeric',
  },
  limit,
  offset,
  locale,
})

export const initLogsTable = ({
  html, fatherElement, part, limit, offset, orderBysStr, logsTab, locale,
}) => new LogsDataTable({
  html,
  fatherElement,
  tableName: 'Application Logs',
  labelRowsPerPage: locale === 'pt-BR' ? 'Linhas por página' : 'Lines per page',
  columns: (logsTab && part.split(',')) || defaultPartLogs.split(','),
  columnsHeaders: {
    id: 'Id',
    timestamp: 'Timestamp',
    severity: locale === 'pt-BR' ? 'Severidade' : 'Severity',
    event: locale === 'pt-BR' ? 'Evento' : 'Event',
    log: 'Log',
  },
  columnsWidths: {
    log: '60%',
  },
  orderBys: orderBysStrToObj((logsTab && orderBysStr) || defaultOrderBysStr),
  defaultOrderBysStr,
  limit,
  offset,
  locale,
})
