import ElasticAPM from 'elastic-apm-node';

import Logger from '@dnorio/logger';

const { logger } = Logger();

if (process.env.APM_SERVER_TOKEN) {
  ElasticAPM.start({
    serviceName: 'my-site-back-end',
    verifyServerCert: false,
    secretToken: process.env.APM_SERVER_TOKEN,
    serverUrl: process.env.APM_SERVER_URL,
    captureBody: 'all', // Default: off
    logLevel: 'info', // Default: info
    logger: {
      fatal: logger.error,
      warn: logger.warn,
      error: logger.error,
      info: logger.info,
      debug: logger.debug,
      trace: logger.debug,
    },
  });
}

export { ElasticAPM };
