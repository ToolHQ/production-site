import {
  getConnection,
  ConnectionType,
  getDbConnsOpts,
} from '@dnorio/db-wrapper';
import Logger from '@dnorio/logger';

import { entities } from '@dnorio/models-toolhq';
import { generateDatabaseDDLFromModel } from '@dnorio/models-generator';

import { computeElapsedTimeMsFromHrTimes } from './timer.js';

import {
  extractQueryMetadata,
  PostgresExtension,
} from '../services/node-sql-parser.js';

import { ParsedSelectOptions } from '@dnorio/pg-query-binding';
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
  connectionName: ConnectionType,
  auditRowsCollection?: unknown[]
) => {
  const rows = await executeQuery<{ one: number }[]>(
    `SELECT 1 ONE FROM pg_database WHERE datname = $1 LIMIT 1`,
    [databaseName],
    {
      connection: connectionName,
      auditRowsCollection,
    }
  );
  return Boolean(rows.length);
};

export const terminateDatabaseConnections = async (
  databaseName: string,
  connectionName: ConnectionType,
  auditRowsCollection?: unknown[]
) => {
  await executeQuery(
    `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1`,
    [databaseName],
    {
      connection: connectionName,
      auditRowsCollection,
    }
  );
};

export const dropDatabase = async (
  databaseName: string,
  connectionName: ConnectionType,
  auditRowsCollection?: unknown[]
) => {
  await executeQuery(`DROP DATABASE ${databaseName}`, [], {
    // TODO: Fix bindings
    connection: connectionName,
    auditRowsCollection,
  });
};

export const doesSchemaExist = async (
  schemaName: string,
  connectionName: ConnectionType,
  auditRowsCollection?: unknown[]
) => {
  const rows = await executeQuery<{ one: number }[]>(
    `SELECT 1 AS one FROM information_schema.schemata WHERE schema_name = $1 LIMIT 1`,
    [schemaName],
    {
      connection: connectionName,
      auditRowsCollection,
    }
  );
  return Boolean(rows.length);
};

export const createDatabase = async (
  databaseName: string,
  connectionName: ConnectionType,
  dropDatabaseIfExists?: boolean,
  auditRowsCollection?: unknown[]
) => {
  const log = logger.infoEvent.bind(this, '#createDatabase');
  const dbExists = await doesDatabaseExists(
    databaseName,
    connectionName,
    auditRowsCollection
  );
  if (dbExists) {
    log(`Database ${databaseName} exists.`);
    if (dropDatabaseIfExists) {
      log(`Database ${databaseName} will be dropped.`);
      await terminateDatabaseConnections(
        databaseName,
        connectionName,
        auditRowsCollection
      );
      await dropDatabase(databaseName, connectionName, auditRowsCollection);
      await executeQuery(`CREATE DATABASE ${databaseName}`, [], {
        connection: connectionName,
        auditRowsCollection,
      }); // TODO: Fix bindings
      log(`Database ${databaseName} created.`);
    }
  } else {
    log(`Database ${databaseName} does not exist.`);
    await executeQuery(`CREATE DATABASE ${databaseName}`, [], {
      connection: connectionName,
      auditRowsCollection,
    }); // TODO: Fix bindings
    log(`Database ${databaseName} created.`);
  }
};

const createDBUser = async ({
  connectionName,
  username,
  password,
  isSuper,
  auditRowsCollection,
}: {
  connectionName: ConnectionType;
  username: string;
  password: string;
  isSuper?: boolean;
  auditRowsCollection?: unknown[];
}) => {
  const log = logger.infoEvent.bind(this, '#createDBUser');

  // Check if the user exists
  const rows = await executeQuery<{ '1': 1 }[]>(
    `SELECT 1 FROM pg_roles WHERE rolname=$1`,
    [username],
    { connection: connectionName, auditRowsCollection }
  );
  const userExists = Boolean(rows.length);

  if (!userExists) {
    // Create a new role
    await executeQuery(
      `CREATE ROLE ${username} WITH LOGIN PASSWORD '${password}'`,
      [],
      { connection: connectionName, auditRowsCollection }
    );
    log(`User ${username} created.`);
  }
  if (isSuper) {
    // Grant superuser privileges
    await executeQuery(`ALTER ROLE ${username} WITH SUPERUSER`, [], {
      connection: connectionName,
      auditRowsCollection,
    });
    log(`User ${username} granted superuser privileges.`);
  } else {
    // Revoke superuser privileges
    await executeQuery(`ALTER ROLE ${username} WITH NOSUPERUSER`, [], {
      connection: connectionName,
      auditRowsCollection,
    });
    log(`User ${username} granted without superuser privileges.`);
  }
};

const createSchema = async ({
  connectionName,
  schemaName,
  auditRowsCollection,
}: {
  connectionName: ConnectionType;
  schemaName: string;
  auditRowsCollection?: unknown[];
}) => {
  const log = logger.infoEvent.bind(this, '#createSchema');
  const schemaExists = await doesSchemaExist(
    schemaName,
    connectionName,
    auditRowsCollection
  );
  if (schemaExists) {
    log(`Schema ${schemaName} exists.`);
  } else {
    log(`Schema ${schemaName} does not exist.`);
    await executeQuery(`CREATE SCHEMA ${schemaName}`, [], {
      connection: connectionName,
      auditRowsCollection,
    });
    log(`Schema ${schemaName} created.`);
  }
};

const grantUsageSchema = async ({
  connectionName,
  schemaName,
  username,
  auditRowsCollection,
}: {
  connectionName: ConnectionType;
  schemaName: string;
  username: string;
  auditRowsCollection?: unknown[];
}) => {
  const log = logger.infoEvent.bind(this, '#grantUsageSchema');
  await executeQuery(`GRANT USAGE ON SCHEMA ${schemaName} TO ${username}`, [], {
    connection: connectionName,
    auditRowsCollection,
  });
  log(`Grant usage on schema ${schemaName} to user ${username} done.`);
};

const enableExtension = async (
  connectionName: ConnectionType,
  extensionName: PostgresExtension,
  auditRowsCollection?: unknown[]
) => {
  await executeQuery(`CREATE EXTENSION IF NOT EXISTS ${extensionName}`, [], {
    connection: connectionName,
    auditRowsCollection,
  });
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
  auditRowsCollection,
}: {
  connectionDefault: ConnectionType;
  connectionName: ConnectionType;
  databaseName?: string;
  schemaName?: string;
  isSuper?: boolean;
  temporarySuper?: boolean;
  extensions?: PostgresExtension[];
  dropDatabaseIfExists?: boolean;
  auditRowsCollection?: unknown[];
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

  await createDatabase(
    database,
    connectionDefault,
    dropDatabaseIfExists,
    auditRowsCollection
  );

  await createDBUser({
    connectionName: connectionDefault,
    username: baseForCreation.user,
    password: baseForCreation.password,
    isSuper: isSuper || temporarySuper,
    auditRowsCollection,
  });
  await createSchema({
    connectionName,
    schemaName: schema,
    auditRowsCollection,
  });
  if (extensions?.length) {
    for (const extension of extensions) {
      await enableExtension(connectionName, extension, auditRowsCollection);
    }
  }
  // Revoke super user
  if (temporarySuper) {
    await createDBUser({
      connectionName: connectionDefault,
      username: baseForCreation.user,
      password: baseForCreation.password,
      isSuper: false,
      auditRowsCollection,
    });
  }
  await grantUsageSchema({
    connectionName,
    schemaName: schema,
    username: baseForCreation.user,
    auditRowsCollection,
  });
};

type EntityName = keyof typeof entities;
type ExcludePartition<T extends string> = T extends `${string}Partition`
  ? never
  : T;

type FilteredEntityName = ExcludePartition<EntityName>;

const createTableWithPartitions = async (
  connectionName: ConnectionType,
  entityName: FilteredEntityName,
  auditRowsCollection?: unknown[]
) => {
  const ddl = generateDatabaseDDLFromModel({
    entity: entities[entityName],
    options: {
      ifNotExists: true,
      generationOptions: {},
    },
  });
  await executeQuery(ddl, [], {
    connection: connectionName,
    auditRowsCollection,
  });
  const ddlPartitions = generateDatabaseDDLFromModel({
    entity: entities[`${entityName}Partition`],
    options: {
      ifNotExists: true,
      generationOptions: {},
    },
  });
  await executeQuery(ddlPartitions, [], {
    connection: connectionName,
    auditRowsCollection,
  });
};

type MakeOptional<T, K extends keyof T> = Omit<T, K> & Partial<Pick<T, K>>;

export const executeGetQueryMetadata = (
  query: string,
  omitStatementObject?: boolean
) => {
  const result = extractQueryMetadata(query);
  if (omitStatementObject) {
    const { statements } = result;
    const newStatements = statements as MakeOptional<
      (typeof statements)[number],
      'stmtObject'
    >[];
    for (const statement of newStatements) {
      delete statement?.stmtObject;
    }
    return {
      version: result.version,
      statements: newStatements,
    };
  }
  return result;
};

/**
 * Inits creation of the dba database and audit structure at the provided instance.
 */
export const executeInitDatabase = async ({
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
  const auditRowsCollection: unknown[] = [];
  // const log = logger.infoEvent.bind(this, '#executeInitDatabase');

  // Creates dba database using connectionDefault
  await createDatabaseUserAndSchemasAndExtensions({
    connectionDefault,
    connectionName: 'postgres_dba',
    isSuper: true,
    extensions: ['dblink'],
    dropDatabaseIfExists,
    auditRowsCollection,
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
    auditRowsCollection,
  });

  await createTableWithPartitions(
    'postgres_dba',
    'ddlAuditLog',
    auditRowsCollection
  );

  return auditRowsCollection;
};

const parseSQLWithHints = (input: string) => {
  const sections = input.split(/-- (SQL|BINDINGS)\n/i);

  // Extract the sections
  const sqlIndex = sections.indexOf('SQL');
  const bindingsIndex = sections.indexOf('BINDINGS');

  const sql: string =
    sqlIndex !== -1 ? sections[sqlIndex + 1]?.trim() || input : input;
  const bindings: string[] =
    bindingsIndex !== -1
      ? sections?.[bindingsIndex + 1]
          ?.trim()
          .split('\n')
          .map((b) => b.trim()) || []
      : [];

  return { sql, bindings };
};

/**
 * Safely replaces PostgreSQL-style $1, $2 placeholders with ? placeholders
 * at the exact positions specified in the positions array.
 *
 * @param {string} sql - The SQL query containing $1, $2, etc. placeholders.
 * @param {number[]} paramsRefs - An array of character positions where each $ placeholder occurs.
 * @param {string[]} bindings - An array of bindings to replace the placeholders with.
 * @returns {{ transformedSql: string; bindingsPerPosition: string[] }} - The transformed SQL query and the bindings in the correct order.
 */
const replacePlaceholdersAtPositions = (
  sql: string,
  paramsRefs: { location: number; i: number }[],
  bindings: string[]
): { transformedSql: string; bindingsPerPosition: string[] } => {
  // Sort positions in descending order to avoid shifting issues when replacing
  const sortedParamsRefs = paramsRefs.sort((a, b) => b.location - a.location);

  let transformedSql = sql;
  const bindingsPerPosition: string[] = [];

  for (const parsedParam of sortedParamsRefs) {
    // Safely replace the exact placeholder at the position with ?
    transformedSql = `${transformedSql.slice(
      0,
      parsedParam.location
    )}?${transformedSql.slice(parsedParam.location + 2)}`;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    bindingsPerPosition.unshift(bindings[parsedParam.i - 1]!);
  }

  return {
    transformedSql,
    bindingsPerPosition,
  };
};

/**
 * Executes the provided SQL query at the provided connection, returning the audit and query metadata and the query results.
 */
export const executeQuery = async <T>(
  sql: string,
  bindings: string[],
  options: {
    connection?: ConnectionType;
    returnRawData?: boolean;
    auditRowsCollection?: unknown[];
  } = {
    connection: 'postgres_default',
    returnRawData: true,
  }
) => {
  // Set default values for options
  const { connection = 'postgres_default', returnRawData = true } = options;

  const auditStartTime = process.hrtime();
  const auditRows = extractQueryMetadata(sql).statements.map((stmt) => ({
    stmt: stmt.stmt,
    stmtKind: stmt.stmtKind,
    stmtSyntax: stmt.stmtSyntax,
    stmtSubCommands: stmt.stmtSubCommands,
    stmtTarget: stmt.stmtTarget,
    stmtOptions: stmt.stmtOptions,
    sql: returnRawData ? sql : '<omitted>',
    bindings: returnRawData ? bindings : '<omitted>',
    stmtObject: returnRawData ? stmt.stmtObject : '<omitted>',
  }));
  const auditElapsedTime = computeElapsedTimeMsFromHrTimes(
    process.hrtime(),
    auditStartTime
  );
  const db = getConnection(connection);
  let finalSql = sql;
  let finalBindings: string[] = bindings;
  if (bindings.length) {
    let paramsRefs: { location: number; i: number }[] = auditRows.reduce(
      (pv, cv) => {
        if ((cv?.stmtOptions as ParsedSelectOptions)?.parsedRefs?.param) {
          return pv.concat(
            (cv.stmtOptions as ParsedSelectOptions).parsedRefs.param
          );
        }
        return pv;
      },
      [] as { location: number; i: number }[]
    );
    if (paramsRefs.length === 0) {
      paramsRefs = sql.split('').reduce((pv, cv, i) => {
        if (cv === '$') {
          pv.push({
            location: i,
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
            i: parseInt(sql[i + 1]!, 10),
          });
        }
        return pv;
      }, [] as { location: number; i: number }[]);
    }

    const { transformedSql, bindingsPerPosition } =
      replacePlaceholdersAtPositions(sql, paramsRefs, bindings);
    finalSql = transformedSql;
    finalBindings = bindingsPerPosition;
  }
  const queryStartTime = process.hrtime();
  const { rows } = bindings.length
    ? await db.raw(finalSql, finalBindings)
    : await db.raw(finalSql);
  const queryElapsedTime = computeElapsedTimeMsFromHrTimes(
    process.hrtime(),
    queryStartTime
  );
  const totalElapsedTime = computeElapsedTimeMsFromHrTimes(
    process.hrtime(),
    auditStartTime
  );
  if (options.auditRowsCollection) {
    options.auditRowsCollection.push(
      ...auditRows.map((row) => ({
        auditElapsedTime,
        queryElapsedTime,
        totalElapsedTime,
        ...row,
      }))
    );
  }
  return rows as T;
};

export const executeRawQuery = async (rawSql: string) => {
  const { sql, bindings } = parseSQLWithHints(rawSql);
  const auditRowsCollection: unknown[] = [];
  const rows = await executeQuery(sql, bindings, {
    returnRawData: false,
    auditRowsCollection,
  });
  return {
    auditRows: auditRowsCollection,
    rows,
  };
};

// SELECT 1 ONE FROM pg_database WHERE datname = $1 LIMIT 1

// SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1
// SELECT 1 FROM pg_roles WHERE rolname='svc_dba'
// CREATE ROLE svc_xpto WITH LOGIN PASSWORD 'xpto'
// ALTER ROLE svc_dba WITH SUPERUSER
// SELECT 1 AS one FROM information_schema.schemata WHERE schema_name = $1 LIMIT 1
// GRANT USAGE ON SCHEMA \"dba_audit\" TO svc_dba
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
