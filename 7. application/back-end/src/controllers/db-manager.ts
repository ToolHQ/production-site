import { RequestHandler } from 'express';

import {
  getConnection,
  ConnectionType,
  getDbConnsOpts,
} from '@dnorio/db-wrapper';
import Logger from '@dnorio/logger';

import { entities } from '@dnorio/models-toolhq';
import { generateDatabaseDDLFromModel } from '@dnorio/models-generator';

import { Empty, InitDatabaseBody, InitDatabaseParams } from '../types.js';

const { logger } = Logger();

// import { rawRequest } from '@dnorio/models-toolhq';

const getCredentialsSchema = (connectionName: ConnectionType) => {
  const { connection, client } = getDbConnsOpts()[connectionName];
  const { user, password } = connection;
  if (client === 'pg') {
    const singleSchema = Array.isArray(connection.searchPath)
      ? connection.searchPath[0]
      : connection.searchPath;
    return {
      database: connection.database,
      schema: singleSchema || 'public',
      user,
      password,
    };
  } else if (client === 'redshift') {
    return {
      database: connection.database,
      schema: connection.schema,
      user,
      password,
    };
  } else if (client === 'mssql') {
    return {
      database: connection.database,
      user,
      password,
    };
  }
  return {
    user,
    password,
  };
};

export const doesDatabaseExists = async (
  databaseName: string,
  connectionName: ConnectionType
) => {
  const db = getConnection(connectionName);
  const { rows } = await db.raw<{ rows: { one: number }[] }>(
    `SELECT 1 ONE FROM pg_database WHERE datname = ? LIMIT 1`,
    [databaseName]
  );
  return Boolean(rows.length);
};

export const doesSchemaExist = async (
  schemaName: string,
  connectionName: ConnectionType
) => {
  const db = getConnection(connectionName);
  const { rows } = await db.raw<{ rows: { one: number }[] }>(
    `SELECT 1 AS one FROM information_schema.schemata WHERE schema_name = ? LIMIT 1`,
    [schemaName]
  );
  return Boolean(rows.length);
};

export const terminateDatabaseConnections = async (
  databaseName: string,
  connectionName: ConnectionType
) => {
  const db = getConnection(connectionName);
  await db.raw(
    `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = ?`,
    [databaseName]
  );
};

export const dropDatabase = async (
  databaseName: string,
  connectionName: ConnectionType
) => {
  const db = getConnection(connectionName);
  await db.raw(`DROP DATABASE ??`, [databaseName]);
};

export const createDatabase = async (
  databaseName: string,
  connectionName: ConnectionType
) => {
  const log = logger.infoEvent.bind(this, '#createDatabase');
  const dbExists = await doesDatabaseExists(databaseName, connectionName);
  if (dbExists) {
    log(`Database ${databaseName} exists.`);
  } else {
    log(`Database ${databaseName} does not exist.`);
    const db = getConnection(connectionName);
    await db.raw(`CREATE DATABASE ??`, [databaseName]);
    log(`Database ${databaseName} created.`);
  }
};

const createDBUser = async ({
  connectionName,
  username,
  password,
  isSuper,
}: {
  connectionName: ConnectionType;
  username: string;
  password: string;
  isSuper?: boolean;
}) => {
  const log = logger.infoEvent.bind(this, '#createDBUser');

  const db = getConnection(connectionName, { logs: false });

  // Check if the user exists
  const { rows } = await db.raw(
    `SELECT 1 FROM pg_roles WHERE rolname='${username}'`
  );
  const userExists = Boolean(rows.length);

  if (!userExists) {
    // Create a new role
    await db.raw(`CREATE ROLE ${username} WITH LOGIN PASSWORD '${password}'`);
    log(`User ${username} created.`);
  }
  if (isSuper) {
    // Grant superuser privileges
    await db.raw(`ALTER ROLE ${username} WITH SUPERUSER`);
    log(`User ${username} granted superuser privileges.`);
  } else {
    // Revoke superuser privileges
    await db.raw(`ALTER ROLE ${username} WITH NOSUPERUSER`);
    log(`User ${username} granted without superuser privileges.`);
  }
};

const createSchema = async ({
  connectionName,
  schemaName,
}: {
  connectionName: ConnectionType;
  schemaName: string;
}) => {
  const log = logger.infoEvent.bind(this, '#createSchema');
  const schemaExists = await doesSchemaExist(schemaName, connectionName);
  if (schemaExists) {
    log(`Schema ${schemaName} exists.`);
  } else {
    log(`Schema ${schemaName} does not exist.`);
    const db = getConnection(connectionName);
    await db.raw(`CREATE SCHEMA ??`, [schemaName]);
    log(`Schema ${schemaName} created.`);
  }
};

const grantUsageSchema = async ({
  connectionName,
  schemaName,
  username,
}: {
  connectionName: ConnectionType;
  schemaName: string;
  username: string;
}) => {
  const log = logger.infoEvent.bind(this, '#grantUsageSchema');
  const db = getConnection(connectionName);
  await db.raw(`GRANT USAGE ON SCHEMA ?? TO ${username}`, [schemaName]);
  log(`Grant usage on schema ${schemaName} to user ${username} done.`);
};

const createDatabaseUserAndSchemas = async ({
  connectionDefault,
  connectionName,
  databaseName,
  schemaName,
  isSuper,
  temporarySuper,
}: {
  connectionDefault: ConnectionType;
  connectionName: ConnectionType;
  databaseName?: string;
  schemaName?: string;
  isSuper?: boolean;
  temporarySuper?: boolean;
}) => {
  // const log = logger.infoEvent.bind(this, '#initDatabase');
  const baseForCreation = getCredentialsSchema(connectionName);
  const database = databaseName || baseForCreation.database;
  const schema = schemaName || baseForCreation.schema;
  if (!database) {
    throw Error('Database must be provided!');
  }
  if (!schema) {
    throw Error('Schema must be provided!');
  }

  await createDatabase(database, connectionDefault);

  await createDBUser({
    connectionName: connectionDefault,
    username: baseForCreation.user,
    password: baseForCreation.password,
    isSuper: isSuper || temporarySuper,
  });
  await createSchema({
    connectionName,
    schemaName: schema,
  });
  if (temporarySuper) {
    await createDBUser({
      connectionName: connectionDefault,
      username: baseForCreation.user,
      password: baseForCreation.password,
      isSuper: false,
    });
  }
  await grantUsageSchema({
    connectionName,
    schemaName: schema,
    username: baseForCreation.user,
  });
};

type EntityName = keyof typeof entities;
type ExcludePartition<T extends string> = T extends `${string}Partition`
  ? never
  : T;

type FilteredEntityName = ExcludePartition<EntityName>;

const createTableWithPartitions = async (
  connectionName: ConnectionType,
  entityName: FilteredEntityName
) => {
  const db = getConnection(connectionName);
  const ddl = generateDatabaseDDLFromModel({
    entity: entities[entityName],
    options: {
      ifNotExists: true,
      generationOptions: {},
    },
  });
  await db.raw(ddl);
  const ddlPartitions = generateDatabaseDDLFromModel({
    entity: entities[`${entityName}Partition`],
    options: {
      ifNotExists: true,
      generationOptions: {},
    },
  });
  await db.raw(ddlPartitions);
};

/**
 * Inits creation of the dba database and audit structure at the provided instance.
 */
const executeInitDatabase = async ({
  connectionDefault,
  connectionName,
  database,
  schema,
}: {
  connectionDefault: ConnectionType;
  connectionName: ConnectionType;
  database?: string;
  schema?: string;
}) => {
  // const log = logger.infoEvent.bind(this, '#executeInitDatabase');

  // Creates dba database using connectionDefault
  await createDatabaseUserAndSchemas({
    connectionDefault,
    connectionName: 'postgres_dba',
    isSuper: true,
  });

  // Creates target database
  await createDatabaseUserAndSchemas({
    connectionDefault,
    connectionName,
    databaseName: database,
    schemaName: schema,
    temporarySuper: true,
  });

  await createTableWithPartitions('postgres_dba', 'ddlAuditLog');
};

export const initDatabase: RequestHandler<
  InitDatabaseParams,
  Empty,
  InitDatabaseBody
> = async (req, res, next) => {
  try {
    const {
      params: { connectionName },
      body: { schema, database },
    } = req;
    await executeInitDatabase({
      connectionDefault: 'postgres_default',
      connectionName,
      database,
      schema,
    });
    res.json({});
  } catch (error) {
    next(error);
  }
};
