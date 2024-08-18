import { RequestHandler } from 'express';

import {
  getConnection,
  ConnectionType,
  getDbConnsOpts,
} from '@dnorio/db-wrapper';
import Logger from '@dnorio/logger';

import { entities } from '@dnorio/models-toolhq';
import { generateDatabaseDDLFromModel } from '@dnorio/models-generator';

import {
  Empty,
  ExecuteQueriesPlainText,
  ExecuteQueriesResponseBody,
  GetQueryMetadataBody,
  GetQueryMetadataResponseBody,
  InitDatabaseBody,
  InitDatabaseParams,
} from '../types.js';

import { extractQueryMetadata } from '../services/node-sql-parser.js';

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
  connectionName: ConnectionType,
  dropDatabaseIfExists?: boolean
) => {
  const log = logger.infoEvent.bind(this, '#createDatabase');
  const dbExists = await doesDatabaseExists(databaseName, connectionName);
  if (dbExists) {
    log(`Database ${databaseName} exists.`);
    if (dropDatabaseIfExists) {
      log(`Database ${databaseName} will be dropped.`);
      await terminateDatabaseConnections(databaseName, connectionName);
      await dropDatabase(databaseName, connectionName);
      const db = getConnection(connectionName);
      await db.raw(`CREATE DATABASE ??`, [databaseName]);
      log(`Database ${databaseName} created.`);
    }
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

  const db = getConnection(connectionName, { logs: true });

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

type PostgresExtension =
  | 'adminpack'
  | 'amcheck'
  | 'autoinc'
  | 'bloom'
  | 'bool_plperl'
  | 'bool_plperlu'
  | 'btree_gin'
  | 'btree_gist'
  | 'citext'
  | 'cube'
  | 'dblink'
  | 'dict_int'
  | 'dict_xsyn'
  | 'earthdistance'
  | 'file_fdw'
  | 'fuzzystrmatch'
  | 'hstore'
  | 'hstore_plperl'
  | 'hstore_plperlu'
  | 'hstore_plpython3u'
  | 'insert_username'
  | 'intagg'
  | 'intarray'
  | 'isn'
  | 'jsonb_plperl'
  | 'jsonb_plperlu'
  | 'jsonb_plpython3u'
  | 'lo'
  | 'ltree'
  | 'ltree_plpython3u'
  | 'moddatetime'
  | 'old_snapshot'
  | 'pageinspect'
  | 'pg_buffercache'
  | 'pg_freespacemap'
  | 'pg_prewarm'
  | 'pg_stat_statements'
  | 'pg_surgery'
  | 'pg_trgm'
  | 'pg_visibility'
  | 'pg_walinspect'
  | 'pgcrypto'
  | 'pgrowlocks'
  | 'pgstattuple'
  | 'plperl'
  | 'plperlu'
  | 'plpgsql'
  | 'plpython3u'
  | 'pltcl'
  | 'pltclu'
  | 'postgres_fdw'
  | 'refint'
  | 'seg'
  | 'sslinfo'
  | 'tablefunc'
  | 'tcn'
  | 'tsm_system_rows'
  | 'tsm_system_time'
  | 'unaccent'
  | 'uuid-ossp'
  | 'xml2';

const enableExtension = async (
  connectionName: ConnectionType,
  extensionName: PostgresExtension
) => {
  const db = getConnection(connectionName);
  await db.raw(`CREATE EXTENSION IF NOT EXISTS ??`, [extensionName]);
};

const createDatabaseUserAndSchemasAndExtensions = async ({
  connectionDefault,
  connectionName,
  databaseName,
  schemaName,
  isSuper,
  temporarySuper,
  extensions,
  dropDatabaseIfExists,
}: {
  connectionDefault: ConnectionType;
  connectionName: ConnectionType;
  databaseName?: string;
  schemaName?: string;
  isSuper?: boolean;
  temporarySuper?: boolean;
  extensions?: PostgresExtension[];
  dropDatabaseIfExists?: boolean;
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

  await createDatabase(database, connectionDefault, dropDatabaseIfExists);

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
  if (extensions?.length) {
    for (const extension of extensions) {
      await enableExtension(connectionName, extension);
    }
  }
  // Revoke super user
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
  dropDatabaseIfExists,
}: {
  connectionDefault: ConnectionType;
  connectionName: ConnectionType;
  database?: string;
  schema?: string;
  dropDatabaseIfExists?: boolean;
}) => {
  // const log = logger.infoEvent.bind(this, '#executeInitDatabase');

  // Creates dba database using connectionDefault
  await createDatabaseUserAndSchemasAndExtensions({
    connectionDefault,
    connectionName: 'postgres_dba',
    isSuper: true,
    extensions: ['dblink'],
    dropDatabaseIfExists,
  });

  // Creates target database
  await createDatabaseUserAndSchemasAndExtensions({
    connectionDefault,
    connectionName,
    databaseName: database,
    schemaName: schema,
    temporarySuper: true,
    extensions: ['dblink'],
    dropDatabaseIfExists,
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
      body: { schema, database, reset },
    } = req;
    await executeInitDatabase({
      connectionDefault: 'postgres_default',
      connectionName,
      database,
      schema,
      dropDatabaseIfExists: reset,
    });
    res.json({});
  } catch (error) {
    next(error);
  }
};

type MakeOptional<T, K extends keyof T> = Omit<T, K> & Partial<Pick<T, K>>;

export const getQueryMetadata: RequestHandler<
  Empty,
  GetQueryMetadataResponseBody,
  GetQueryMetadataBody
> = async (req, res, next) => {
  try {
    const result = extractQueryMetadata(req.body.query);
    if (req.body.omitStatementObject) {
      const { statements } = result;
      const newStatements = statements as MakeOptional<
        (typeof statements)[number],
        'stmtObject'
      >[];
      for (const statement of newStatements) {
        delete statement?.stmtObject;
      }
      res.json({
        version: result.version,
        statements: newStatements,
      });
      return;
    }
    res.json(result);
  } catch (error) {
    next(error);
  }
};

export const executeQueries: RequestHandler<
  Empty,
  ExecuteQueriesResponseBody,
  ExecuteQueriesPlainText
> = async (req, res, next) => {
  try {
    const { body: sql } = req;
    const auditRows = extractQueryMetadata(sql).statements.map((stmt) => ({
      stmt: stmt.stmt,
      stmtKind: stmt.stmtKind,
      stmtSyntax: stmt.stmtSyntax,
      stmtSubCommands: stmt.stmtSubCommands,
      stmtTarget: stmt.stmtTarget,
      stmtOptions: stmt.stmtOptions,
      sql,
      stmtObject: stmt.stmtObject,
    }));
    const db = getConnection('postgres_default');
    const { rows } = await db.raw(sql);
    res.json({ auditRows, rows });
  } catch (error) {
    next(error);
  }
};

// SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1
// SELECT 1 FROM pg_roles WHERE rolname='svc_dba'
// CREATE ROLE svc_xpto WITH LOGIN PASSWORD 'xpto'
// ALTER ROLE svc_dba WITH SUPERUSER
// SELECT 1 AS one FROM information_schema.schemata WHERE schema_name = $1 LIMIT 1
// GRANT USAGE ON SCHEMA \"dba_audit\" TO svc_dba
// SELECT 1 ONE FROM pg_database WHERE datname = $1 LIMIT 1
// SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1
// "SELECT 1 FROM pg_roles WHERE rolname='svc_toolhq'
// ALTER ROLE svc_toolhq WITH SUPERUSER
// SELECT 1 AS one FROM information_schema.schemata WHERE schema_name = $1 LIMIT 1
// SELECT 1 FROM pg_roles WHERE rolname='svc_toolhq'
// ALTER ROLE svc_toolhq WITH NOSUPERUSER
// GRANT USAGE ON SCHEMA \"toolhq\" TO svc_toolhq
// create or replace\nfunction get_public_uuid(internal_id uuid, created_at timestamp, pk int4)\n  returns uuid\n language sql\n immutable strict\nas $$\nselect (to_hex((concat('1', LPAD(pk::text, 11, '0')))::bigint) || EXTRACT(EPOCH FROM created_at::date) || right((internal_id)::varchar, 12))::uuid;\n$$;"
// create table if not exists dba_audit.tb_ddl_audit_log (\n  id_ddl_audit_log int4 not null generated by default as identity(sequence name dba_audit.tb_ddl_audit_log_id_ddl_audit_log_seq),\n  internal_id uuid not null default gen_random_uuid(),\n  created_at timestamp not null default timezone('utc', now()),\n  id uuid not null generated always as (get_public_uuid(internal_id, created_at, id_ddl_audit_log)) stored,\n  operation_type varchar not null,\n  ddl_statement text not null,\n  executed_by varchar not null,\n  execution_time timestamptz not null default timezone('utc', now()),\n  status varchar not null,\n  error_message varchar null,\n  rows_affected int4 null default 0,\n  elapsed_time interval null,\n  text_search tsvector null generated always as (to_tsvector('english', coalesce(ddl_statement, '') || ' ' || coalesce(operation_type, '') || ' ' || coalesce(error_message, ''))) stored,\n  unique (internal_id, created_at),\n  primary key (id_ddl_audit_log, created_at),\n  check (operation_type IN ('ABORT', 'ALTER AGGREGATE', 'ALTER COLLATION', 'ALTER CONVERSION', 'ALTER DATABASE', 'ALTER DEFAULT PRIVILEGES', 'ALTER DOMAIN', 'ALTER EVENT TRIGGER', 'ALTER EXTENSION', 'ALTER FOREIGN DATA WRAPPER', 'ALTER FOREIGN TABLE', 'ALTER FUNCTION', 'ALTER GROUP', 'ALTER INDEX', 'ALTER LANGUAGE', 'ALTER LARGE OBJECT', 'ALTER MATERIALIZED VIEW', 'ALTER OPERATOR', 'ALTER OPERATOR CLASS', 'ALTER OPERATOR FAMILY', 'ALTER POLICY', 'ALTER PROCEDURE', 'ALTER PUBLICATION', 'ALTER ROLE', 'ALTER ROUTINE', 'ALTER RULE', 'ALTER SCHEMA', 'ALTER SEQUENCE', 'ALTER SERVER', 'ALTER STATISTICS', 'ALTER SUBSCRIPTION', 'ALTER SYSTEM', 'ALTER TABLE', 'ALTER TABLESPACE', 'ALTER TEXT SEARCH CONFIGURATION', 'ALTER TEXT SEARCH DICTIONARY', 'ALTER TEXT SEARCH PARSER', 'ALTER TEXT SEARCH TEMPLATE', 'ALTER TRIGGER', 'ALTER TYPE', 'ALTER USER', 'ALTER USER MAPPING', 'ALTER VIEW', 'ANALYZE', 'BEGIN', 'CALL', 'CHECKPOINT', 'CLOSE', 'CLUSTER', 'COMMENT', 'COMMIT', 'COMMIT PREPARED', 'COPY', 'CREATE ACCESS METHOD', 'CREATE AGGREGATE', 'CREATE CAST', 'CREATE COLLATION', 'CREATE CONVERSION', 'CREATE DATABASE', 'CREATE DOMAIN', 'CREATE EVENT TRIGGER', 'CREATE EXTENSION', 'CREATE FOREIGN DATA WRAPPER', 'CREATE FOREIGN TABLE', 'CREATE FUNCTION', 'CREATE GROUP', 'CREATE INDEX', 'CREATE LANGUAGE', 'CREATE MATERIALIZED VIEW', 'CREATE OPERATOR', 'CREATE OPERATOR CLASS', 'CREATE OPERATOR FAMILY', 'CREATE POLICY', 'CREATE PROCEDURE', 'CREATE PUBLICATION', 'CREATE ROLE', 'CREATE RULE', 'CREATE SCHEMA', 'CREATE SEQUENCE', 'CREATE SERVER', 'CREATE STATISTICS', 'CREATE SUBSCRIPTION', 'CREATE TABLE', 'CREATE TABLE AS', 'CREATE TABLESPACE', 'CREATE TEXT SEARCH CONFIGURATION', 'CREATE TEXT SEARCH DICTIONARY', 'CREATE TEXT SEARCH PARSER', 'CREATE TEXT SEARCH TEMPLATE', 'CREATE TRANSFORM', 'CREATE TRIGGER', 'CREATE TYPE', 'CREATE USER', 'CREATE USER MAPPING', 'CREATE VIEW', 'DEALLOCATE', 'DECLARE', 'DELETE', 'DISCARD', 'DO', 'DROP ACCESS METHOD', 'DROP AGGREGATE', 'DROP CAST', 'DROP COLLATION', 'DROP CONVERSION', 'DROP DATABASE', 'DROP DOMAIN', 'DROP EVENT TRIGGER', 'DROP EXTENSION', 'DROP FOREIGN DATA WRAPPER', 'DROP FOREIGN TABLE', 'DROP FUNCTION', 'DROP GROUP', 'DROP INDEX', 'DROP LANGUAGE', 'DROP MATERIALIZED VIEW', 'DROP OPERATOR', 'DROP OPERATOR CLASS', 'DROP OPERATOR FAMILY', 'DROP OWNED', 'DROP POLICY', 'DROP PROCEDURE', 'DROP PUBLICATION', 'DROP ROLE', 'DROP ROUTINE', 'DROP RULE', 'DROP SCHEMA', 'DROP SEQUENCE', 'DROP SERVER', 'DROP STATISTICS', 'DROP SUBSCRIPTION', 'DROP TABLE', 'DROP TABLESPACE', 'DROP TEXT SEARCH CONFIGURATION', 'DROP TEXT SEARCH DICTIONARY', 'DROP TEXT SEARCH PARSER', 'DROP TEXT SEARCH TEMPLATE', 'DROP TRANSFORM', 'DROP TRIGGER', 'DROP TYPE', 'DROP USER', 'DROP USER MAPPING', 'DROP VIEW', 'END', 'EXECUTE', 'EXPLAIN', 'FETCH', 'GRANT', 'IMPORT FOREIGN SCHEMA', 'INSERT', 'LISTEN', 'LOAD', 'LOCK', 'MERGE', 'MOVE', 'NOTIFY', 'PREPARE', 'PREPARE TRANSACTION', 'REASSIGN OWNED', 'REFRESH MATERIALIZED VIEW', 'REINDEX', 'RELEASE SAVEPOINT', 'RESET', 'REVOKE', 'ROLLBACK', 'ROLLBACK PREPARED', 'ROLLBACK TO SAVEPOINT', 'SAVEPOINT', 'SECURITY LABEL', 'SELECT', 'SELECT INTO', 'SET', 'SET CONSTRAINTS', 'SET ROLE', 'SET SESSION AUTHORIZATION', 'SET TRANSACTION', 'SHOW', 'START TRANSACTION', 'TRUNCATE', 'UNLISTEN', 'UPDATE', 'VACUUM', 'VALUES')),\n  check (status = 'success' OR status = 'failed')\n)\npartition by range (created_at);
// create table if not exists dba_audit.yearly_tb_ddl_audit_log_y2024m01d01 partition of dba_audit.tb_ddl_audit_log for values from ('2024-01-01') TO ('2025-01-01');\ncreate table if not exists dba_audit.yearly_tb_ddl_audit_log_y2025m01d01 partition of dba_audit.tb_ddl_audit_log for values from ('2025-01-01') TO ('2026-01-01');\ncreate table if not exists dba_audit.yearly_tb_ddl_audit_log_y2026m01d01 partition of dba_audit.tb_ddl_audit_log for values from ('2026-01-01') TO ('2027-01-01');\ncreate table if not exists dba_audit.yearly_tb_ddl_audit_log_y2027m01d01 partition of dba_audit.tb_ddl_audit_log for values from ('2027-01-01') TO ('2028-01-01');\ncreate table if not exists dba_audit.yearly_tb_ddl_audit_log_y2028m01d01 partition of dba_audit.tb_ddl_audit_log for values from ('2028-01-01') TO ('2029-01-01');\ncreate table if not exists dba_audit.yearly_tb_ddl_audit_log_y2029m01d01 partition of dba_audit.tb_ddl_audit_log for values from ('2029-01-01') TO ('2030-01-01');\ncreate table if not exists dba_audit.yearly_tb_ddl_audit_log_y2030m01d01 partition of dba_audit.tb_ddl_audit_log for values from ('2030-01-01') TO ('2031-01-01');\ncreate table if not exists dba_audit.yearly_tb_ddl_audit_log_y2031m01d01 partition of dba_audit.tb_ddl_audit_log for values from ('2031-01-01') TO ('2032-01-01');\ncreate table if not exists dba_audit.yearly_tb_ddl_audit_log_y2032m01d01 partition of dba_audit.tb_ddl_audit_log for values from ('2032-01-01') TO ('2033-01-01');\ncreate table if not exists dba_audit.yearly_tb_ddl_audit_log_y2033m01d01 partition of dba_audit.tb_ddl_audit_log for values from ('2033-01-01') TO ('2034-01-01');
