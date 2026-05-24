import webpack from 'webpack'

import { log } from './logger.js'
import webpackConfig from './webpack.config.js'

export const runWebpack = () => new Promise((resolve, reject) => {
  const hrTimeStart = process.hrtime()
  webpack(webpackConfig, (err, stats) => {
    const hrTimeElapsed = process.hrtime(hrTimeStart)
    const timeElapsed = `${(hrTimeElapsed[0] * 1000 + hrTimeElapsed[1] / 1000000).toFixed(3)}ms`
    if (err) {
      log('runWebpack ERROR', {
        name: err.name, message: err.message, stack: err.stack, timeElapsed,
      })
      reject(err)
    } else if (stats.hasErrors()) {
      log('runWebpack ERROR', { timeElapsed, errors: stats.toJson().errors.map((e) => ({ name: e.name, message: e.message })) })
      reject(Error('runWebpack ERROR'))
    } else {
      const result = { timeElapsed }
      const statsJson = stats.toJson()
      if (statsJson.warnings.length) {
        result.warnings = statsJson.warnings.map((w) => w.message)
      }
      log('Webpack tasks done!', result)
      resolve(stats)
    }
  })
})

const doJob = async () => {
  try {
    await runWebpack()
    process.send('OK')
  } catch (err) {
    log('Webpack tasks ERROR!', err)
    process.send('NOT OK')
  }
}

doJob()
