module.exports = {
  apps: [
    {
      name: 'qdbback-api',
      script: 'index.js',
    },
    {
      name: 'clickhouse-shipper',
      script: 'scripts/clickhouse-shipper.js',
      env: {
        NODE_ENV: 'production',
        QDBBACK_DB_PATH: '/home/ubuntu/qdbback/database.sqlite'
      }
    },
    {
      name: 'purge-old-data',
      script: 'scripts/purge-old-data.js',
      cron_restart: '0 4 * * *',
      autorestart: false,
      env: {
        QDBBACK_REQUESTS_KEEP_DAYS: '7',
        QDBBACK_DB_PATH: '/home/ubuntu/qdbback/database.sqlite'
      }
    }
  ]
};
