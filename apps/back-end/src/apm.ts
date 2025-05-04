import ElasticAPM, { LogLevel } from 'elastic-apm-node';

import Logger from '@dnorio/logger';
import { setListener } from '@dnorio/db-wrapper';
import { Knex } from 'knex';

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
      debug: logger.debug,
      trace: logger.debug,
    },
    transactionMaxSpans: 1000, // Default: 500
    spanCompressionEnabled: false, // Default: true
    ignoreUrls: ['/health'],
    instrument: true,
    disableInstrumentations: [],
  });

  // Add APM transaction ID to logs
  Logger.addWrapper((obj: Record<string, unknown>) => {
    const idsObj = apm.currentTransaction ? apm.currentTransaction.ids : null;
    if (idsObj) {
      obj.apm = idsObj;
    }
    return obj;
  });

  type KnexPoolMetrics = {
    used: number;
    free: number;
    pendingAcquires: number;
    pendingCreates: number;
    min: number;
    max: number;
  };

  const getKnexPoolMetrics = (knex: Knex): KnexPoolMetrics => ({
    used: knex.client.pool.numUsed(), // Active connections
    free: knex.client.pool.numFree(), // Idle connections
    pendingAcquires: knex.client.pool.numPendingAcquires(), // Waiting for a connection
    pendingCreates: knex.client.pool.numPendingCreates(), // New connections being created
    min: knex.client.pool.min, // Min connections allowed
    max: knex.client.pool.max, // Max connections allowed
  });

  const knexConns = new Map<string, KnexPoolMetrics>();
  // const { setListener } = await import('@dnorio/db-wrapper');

  setListener({
    event: 'start',
    listener: (db: Knex) => {
      const key = `${db.client.config.client}-${db.client.config.connection?.host}-${db.client.config.connection?.database}-${db.client.config.connection?.searchPath}`;
      if (!knexConns.has(key)) {
        const poolMetrics = getKnexPoolMetrics(db);
        knexConns.set(key, poolMetrics);
        apm.registerMetric(
          'knex.pool.used',
          { module: 'knex', connectionKey: key },
          () => knexConns.get(key)?.used
        );
        apm.registerMetric(
          'knex.pool.free',
          { module: 'knex', connectionKey: key },
          () => knexConns.get(key)?.free
        );
        apm.registerMetric(
          'knex.pool.pendingAcquires',
          { module: 'knex', connectionKey: key },
          () => knexConns.get(key)?.pendingAcquires
        );
        apm.registerMetric(
          'knex.pool.pendingCreates',
          { module: 'knex', connectionKey: key },
          () => knexConns.get(key)?.pendingCreates
        );
        apm.registerMetric(
          'knex.pool.min',
          { module: 'knex', connectionKey: key },
          () => knexConns.get(key)?.min
        );
        apm.registerMetric(
          'knex.pool.max',
          { module: 'knex', connectionKey: key },
          () => knexConns.get(key)?.max
        );
        setInterval(() => {
          const poolMetrics = getKnexPoolMetrics(db);
          knexConns.set(key, poolMetrics);
          logger.debugEvent('KnexPoolMetricsToAPM', { poolMetrics, key });
        }, 5000);
      }
    },
  });
}

export { ElasticAPM };
