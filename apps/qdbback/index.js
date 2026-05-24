import http from 'http'
import https from 'https'
import path from 'path'
import { fork } from 'child_process'
import { watch, existsSync } from 'fs'
import {
  port, portHttps, portAdmin, isProduction,
} from './config.js'
import { log } from './logger.js'
import { readFileAsync } from './services/fs.js'
import { getRouter as getMainRouter } from './routers/mainRouter.js'
import { getRouter as getProductionHttpRouter } from './routers/productionHttpRouter.js'
import { getRouter as getMonitoringRouter } from './routers/monitoringRouter.js'
import { init as sqlite3Init } from './sqlite3.js'
import { __dirname } from './dir.js'

const monitorDistIndex = path.join(__dirname, './dist/monitor/index.html')

const webpack = () => new Promise((resolve, reject) => {
  const hrTimeStart = process.hrtime()
  const job = fork(path.join(__dirname, './webpack.js'), { cwd: __dirname })

  job.on('message', (result) => {
    const hrTimeElapsed = process.hrtime(hrTimeStart)
    const timeElapsed = `${(hrTimeElapsed[0] * 1000 + hrTimeElapsed[1] / 1000000).toFixed(3)}ms`
    log('Webpack bridge ending', { timeElapsed })
    if (result === 'OK') {
      resolve()
    } else {
      reject(Error('webpack ERROR'))
    }
  })
})

const runWebpackIfNeeded = () => {
  if (isProduction && existsSync(monitorDistIndex)) {
    log('Skipping webpack in production (dist/monitor present)', {})
    return Promise.resolve()
  }
  return webpack()
}

const beingChanged = new Map()
if (!isProduction) {
  watch(path.resolve(__dirname, './assets/monitor'), async (eventType, filename) => {
    if (!beingChanged.has(filename)) {
      process.stdout.write(`${filename} ${eventType}d...\n`)
      // give 10 seconds for multiple events
      beingChanged.set(filename, setTimeout(() => beingChanged.delete(filename), 10000))
      await webpack()
    }
  })
  watch(path.resolve(__dirname, './assets/monitor/components'), async (eventType, filename) => {
    if (!beingChanged.has(filename)) {
      process.stdout.write(`${filename} ${eventType}d...\n`)
      // give 10 seconds for multiple events
      beingChanged.set(filename, setTimeout(() => beingChanged.delete(filename), 10000))
      await webpack()
    }
  })
}

// Sets to measure time & log request
const hrTimeStart = process.hrtime()

const getCertOptions = async () => {
  const [key, cert] = await Promise.all([
    readFileAsync('../private.key'),
    readFileAsync('../certificate.crt'),
  ])
  return { key, cert }
}

const formatMemoryUsage = (data) => `${Math.round(((data / 1024) / 1024) * 100) / 100} MB`

/**
 * Starts all listeners
 */
const startApp = async () => {
  const depsLoadPromise = Promise.all([
    runWebpackIfNeeded(),
    sqlite3Init(),
  ])
  const mainRouter = getMainRouter()
  const monitoringRouter = getMonitoringRouter(isProduction)
  await depsLoadPromise
  let httpRouter = mainRouter
  let sysAdminCreateServerFunction = http.createServer
  let sysAdminServerOptions = {}
  if (isProduction) {
    httpRouter = getProductionHttpRouter()
    const certOptions = await getCertOptions()
    sysAdminServerOptions = certOptions
    sysAdminCreateServerFunction = https.createServer
    await new Promise((resolve) => https.createServer(certOptions,
      (req, res) => mainRouter.handle(req, res)).listen(portHttps, () => {
      log('Secure Webserver started!', { port: portHttps })
      resolve()
    }))
  }
  await new Promise((resolve) => http.createServer((req, res) => httpRouter
    .handle(req, res)).listen(port, () => {
    log('Webserver started!', { port })
    resolve()
  }))
  await new Promise((resolve) => sysAdminCreateServerFunction(sysAdminServerOptions,
    (req, res) => monitoringRouter.handle(req, res)).listen(portAdmin, () => {
    log('SysAdmin Webserver started!', { port: portAdmin })
    resolve()
  }))
  const hrTimeElapsed = process.hrtime(hrTimeStart)
  const timeElapsed = `${(hrTimeElapsed[0] * 1000 + hrTimeElapsed[1] / 1000000).toFixed(3)}ms`
  const memoryUsage = process.memoryUsage()
  log('End of App Initialization', {
    rss: `${formatMemoryUsage(memoryUsage.rss)} -> Resident Set Size - total memory allocated for the process execution`,
    heapTotal: `${formatMemoryUsage(memoryUsage.heapTotal)} -> total size of the allocated heap`,
    heapUsed: `${formatMemoryUsage(memoryUsage.heapUsed)} -> actual memory used during the execution`,
    external: `${formatMemoryUsage(memoryUsage.external)} -> V8 external memory`,
    timeElapsed,
  })
}

startApp()
