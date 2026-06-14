export const defaultOrderBysStr = 'desc(id)'
export const defaultPartRequests = 'id,timestamp,method,path,timeElapsed,remoteHostname,statusCode'
export const defaultPartLogs = 'id,timestamp,severity,event,log'

export const getUrlState = () => {
  const url = new URL(window.location.href)
  const logsTab = url.pathname.endsWith('/logs')
  const sqlTab = url.pathname.endsWith('/sql')
  const statusTab = url.pathname.endsWith('/status')
  const defaultPart = logsTab ? defaultPartLogs : defaultPartRequests
  const defaultLimit = 20
  const defaultOffset = 0
  const part = url.searchParams.get('part') || defaultPart
  const limit = (url.searchParams.get('limit') && Number(url.searchParams.get('limit'))) || defaultLimit
  const offset = (url.searchParams.get('offset') && Number(url.searchParams.get('offset'))) || defaultOffset
  const orderBysStr = url.searchParams.get('sort_by') || defaultOrderBysStr
  if (part !== defaultPart) {
    url.searchParams.set('part', part)
  }
  if (limit !== defaultLimit) {
    url.searchParams.set('limit', limit)
  }
  if (offset !== defaultOffset) {
    url.searchParams.set('offset', offset)
  }
  if (orderBysStr !== defaultOrderBysStr) {
    url.searchParams.set('sort_by', orderBysStr)
  }
  const newUrl = url.toString()

  if (window.location.href !== newUrl) {
    window.location.href = newUrl
  }

  return {
    part,
    limit,
    offset,
    orderBysStr,
    logsTab,
    requestsTab: !logsTab && !sqlTab && !statusTab,
  }
}
