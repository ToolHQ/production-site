import ElasticAPM, { LogLevel } from 'elastic-apm-node';

import Logger from '@dnorio/logger';

const { logger } = Logger();

if (process.env.ELASTIC_APM_SERVER_TOKEN) {
  const apm = ElasticAPM.start({
    serviceName: 'my-site-back-end',
    verifyServerCert: false,
    secretToken: process.env.ELASTIC_APM_SERVER_TOKEN,
    serverUrl: process.env.ELASTIC_APM_SERVER_URL,
    captureBody: 'all', // Default: off
    logLevel: (process.env.ELASTIC_APM_LOG_LEVEL as LogLevel) || 'info', // Default: info
    logger: {
      fatal: logger.error,
      warn: logger.warn,
      error: logger.error,
      info: logger.info,
      debug: logger.info,
      trace: logger.info,
    },
    transactionMaxSpans: 1000, // Default: 500
    spanCompressionEnabled: false, // Default: true
    ignoreUrls: ['/health'],
  });
  Logger.addWrapper((obj: Record<string, unknown>) => {
    const idsObj = apm.currentTransaction ? apm.currentTransaction.ids : null;
    if (!idsObj) {
      return obj;
    }
    obj = {
      ...obj,
      apm: idsObj,
    };
    return obj;
  });
}

export { ElasticAPM };
