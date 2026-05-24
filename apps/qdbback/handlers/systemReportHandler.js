import systeminformation from 'systeminformation'

import { mimeTypes } from '../constants.js'
import { logger } from '../logger.js'

const formatMemoryUsageFromKibToMb = (data) => `${Math.round(((data / 1024) / 1024) * 100) / 100} MB`

const formatMemoryUsageFromKbToMb = (data) => `${Math.round(((data / 1000) / 1000) * 100) / 100} MB`

const formatPercentage = (data, total) => `${((data / total) * 100).toFixed(2)}%`
const formatAlreadyPercentage = (data) => `${data.toFixed(2)}%`

const hrTimeStart = process.hrtime()

const pad = (n) => (n < 10 ? `0${n}` : n)

const timeUp = (millis) => {
  const cd = 24 * 60 * 60 * 1000
  const ch = 60 * 60 * 1000
  let d = Math.floor(millis / cd)
  let h = Math.floor((millis - d * cd) / ch)
  let m = Math.round((millis - d * cd - h * ch) / 60000)
  if (m === 60) {
    h++
    m = 0
  }
  if (h === 24) {
    d++
    h = 0
  }
  return `${d} day(s), ${pad(h)} hour(s) and ${pad(m)} min(s)`
}

/**
 * @type {import('../router').RequestListener}
 */
export const systemReportHandler = async (req, res) => {
  try {
    const { query: { mode = 'summary' } } = req
    let results
    if (mode === 'raw') {
      results = await systeminformation.getAllData()
    } else {
      const [
        rawMemoryData,
        rawCurrentLoadData,
        rawVersionsData,
        osInfo,
        rawProcessesData,
      ] = await Promise.all([
        systeminformation.mem(),
        systeminformation.currentLoad(),
        systeminformation.versions(),
        systeminformation.osInfo(),
        systeminformation.processes(),
      ])
      const rawVersionsDataEntries = Object.entries(rawVersionsData)
      const versions = {}
      for (const [key, value] of rawVersionsDataEntries) {
        if (value) {
          // eslint-disable-next-line security/detect-object-injection
          versions[key] = value
        }
      }

      const {
        memRssTotal,
        memVszTotal,
        memTotalTotal,
        processesByStatus,
      } = rawProcessesData.list.reduce((pv, cv) => {
        const newProcessesByStatus = {
          running: pv.processesByStatus.running,
          sleeping: pv.processesByStatus.sleeping,
          blocked: pv.processesByStatus.blocked,
          unknown: pv.processesByStatus.unknown,
          zombie: pv.processesByStatus.zombie,
        }
        if (cv.state === 'running') {
          newProcessesByStatus.running++
        }
        if (cv.state === 'sleeping') {
          newProcessesByStatus.sleeping++
        }
        if (cv.state === 'blocked') {
          newProcessesByStatus.blocked++
        }
        if (cv.state === 'unknown') {
          newProcessesByStatus.unknown++
        }
        if (cv.state === 'zombie') {
          newProcessesByStatus.zombie++
        }
        return {
          memRssTotal: cv.memRss + pv.memRssTotal,
          memVszTotal: (cv.memVsz / 1000) + pv.memVszTotal,
          memTotalTotal: cv.memRss + (cv.memVsz / 1000) + pv.memTotalTotal,
          processesByStatus: newProcessesByStatus,
        }
      }, {
        memRssTotal: 0,
        memVszTotal: 0,
        memTotalTotal: 0,
        processesByStatus: {
          running: 0,
          sleeping: 0,
          blocked: 0,
          unknown: 0,
          zombie: 0,
        },
      })
      const processes = {
        total: rawProcessesData.list.length,
        all: rawProcessesData.all,
        running: processesByStatus.running,
        blocked: processesByStatus.blocked,
        sleeping: processesByStatus.sleeping,
        unknown: processesByStatus.unknown,
        zombie: processesByStatus.zombie,
        memRssTotal: formatMemoryUsageFromKbToMb(memRssTotal * 1000),
        memVszTotal: formatMemoryUsageFromKbToMb(memVszTotal * 1000),
        memRssTotalPlusAvailable: formatMemoryUsageFromKbToMb((rawMemoryData.available + memRssTotal) * 1000),
        memVszTotalPlusAvailable: formatMemoryUsageFromKbToMb((rawMemoryData.available + memVszTotal) * 1000),
        memTotalTotal: formatMemoryUsageFromKbToMb(memTotalTotal * 1000),
        list: rawProcessesData.list.sort((processA, processB) => {
          if (processA.memRss > processB.memRss) {
            return -1
          }
          if (processA.memRss < processB.memRss) {
            return 1
          }
          if (processA.memVsz > processB.memVsz) {
            return -1
          }
          if (processA.memVsz < processB.memVsz) {
            return 1
          }
          return 0
        }).map((process) => ({
          ...process,
          rss: formatMemoryUsageFromKibToMb(process.memRss * 1000),
          rssPercentage: formatPercentage(process.memRss, memRssTotal),
        })),
      }

      const hrTimeElapsed = process.hrtime(hrTimeStart)
      const timeElapsed = timeUp(hrTimeElapsed[0] * 1000 + hrTimeElapsed[1] / 1000000)
      const memoryUsage = process.memoryUsage()
      const nodeMemoryUsage = {
        rss: formatMemoryUsageFromKibToMb(memoryUsage.rss),
        rssRaw: memoryUsage.rss,
        heapTotal: formatMemoryUsageFromKibToMb(memoryUsage.heapTotal),
        heapUsed: formatMemoryUsageFromKibToMb(memoryUsage.heapUsed),
        external: formatMemoryUsageFromKibToMb(memoryUsage.external),
      }

      results = {
        memory: {
          total: formatMemoryUsageFromKbToMb(rawMemoryData.total),
          free: formatMemoryUsageFromKbToMb(rawMemoryData.free),
          used: formatMemoryUsageFromKbToMb(rawMemoryData.used),
          available: formatMemoryUsageFromKbToMb(rawMemoryData.available),
          percentageAvailable: formatPercentage(rawMemoryData.available, rawMemoryData.total),
          percentageUnavailable: formatPercentage(rawMemoryData.total - rawMemoryData.available, rawMemoryData.total),
          percentageFree: formatPercentage(rawMemoryData.free, rawMemoryData.total),
          percentageUsed: formatPercentage(rawMemoryData.used, rawMemoryData.total),
        },
        nodeMemoryUsage,
        cpu: {
          currentLoad: formatAlreadyPercentage(rawCurrentLoadData.currentLoad),
          currentLoadIdle: formatAlreadyPercentage(rawCurrentLoadData.currentLoadIdle),
          currentLoadUser: formatAlreadyPercentage(rawCurrentLoadData.currentLoadUser),
          currentLoadSystem: formatAlreadyPercentage(rawCurrentLoadData.currentLoadSystem),
        },
        timeElapsed,
        versions,
        osInfo,
        processes,
      }
    }

    res
      .writeHead(200, {
        'Content-Type': mimeTypes.json,
      })
      .end(JSON.stringify(results))
  } catch (err) {
    logger.error('systemReportHandler ERROR', { cause: err.message, stack: err.stack })
    res.writeHead(500)
  }
  res.end()
}
