import { RequestHandler } from 'express';

import { getConnection } from '@dnorio/db-wrapper';
import Logger from '@dnorio/logger';

import { InitDatabaseParams } from '../types';

const { logger } = Logger();

// import { rawRequest } from '@dnorio/models-toolhq';

type ValidConnections = 'postgres' | 'oracledb' | 'redshift' | 'mssql';

export const doesDatabaseExists = async ({
  connectionName,
  databaseName,
}: {
  connectionName: ValidConnections;
  databaseName?: string;
}) => {
  const db = getConnection(connectionName);
  const { rows } = await db.raw<{ rows: { one: number }[] }>(
    `SELECT 1 ONE FROM pg_database WHERE datname = ? LIMIT 1`,
    [databaseName]
  );
  return Boolean(rows.length);
};

export const terminateDatabaseConnections = async ({
  connectionName,
  databaseName,
}: {
  connectionName: ValidConnections;
  databaseName?: string;
}) => {
  const db = getConnection(connectionName);
  await db.raw(
    `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = ?`,
    [databaseName]
  );
};

export const dropDatabase = async ({
  connectionName,
  databaseName,
}: {
  connectionName: ValidConnections;
  databaseName?: string;
}) => {
  const db = getConnection(connectionName);
  await db.raw(`DROP DATABASE ??`, [databaseName]);
};

export const createDatabase = async ({
  connectionName,
  databaseName,
}: {
  connectionName: ValidConnections;
  databaseName?: string;
}) => {
  const db = getConnection(connectionName);
  await db.raw(`CREATE DATABASE ??`, [databaseName]);
};

const executeInitDatabase = async ({
  connectionName,
  databaseName,
}: {
  connectionName: ValidConnections;
  databaseName?: string;
}) => {
  const baseParams = {
    connectionName,
    databaseName,
  };
  const dbExists = await doesDatabaseExists(baseParams);

  const log = logger.infoEvent.bind(this, '#executeInitDatabase');
  if (dbExists) {
    log(`Database ${databaseName} exists. Dropping it...`);

    // Terminate active connections to the database
    await terminateDatabaseConnections(baseParams);

    // Drop the database
    await dropDatabase(baseParams);

    log(`Database ${databaseName} dropped.`);
  } else {
    log(`Database ${databaseName} does not exist.`);
  }

  // Create the database
  await createDatabase(baseParams);
  log(`Database ${databaseName} created.`);

  return {
    databaseExists: dbExists,
  };
};

export const initDatabase: RequestHandler<InitDatabaseParams> = async (
  req,
  res,
  next
) => {
  try {
    const {
      params: { connectionName },
    } = req;
    const result = await executeInitDatabase({
      connectionName,
      databaseName: 'dba',
    });
    res.json(result);
  } catch (error) {
    next(error);
  }
};
