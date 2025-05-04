import { ConnectionType, getDbConnsOpts } from '@dnorio/db-wrapper';
import Logger from '@dnorio/logger';

import { entities } from '@dnorio/models-toolhq';
import { generateDatabaseDDLFromModel } from '@dnorio/models-generator';

import {
  extractQueryMetadata,
  PostgresExtension,
} from '../services/node-sql-parser.js';

const { logger } = Logger();

import { executeQuery, saveAuditRows, AuditRow } from './execute-query.js';

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
  auditRowsCollection?: AuditRow[]
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
  auditRowsCollection?: AuditRow[]
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
  auditRowsCollection?: AuditRow[]
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
  auditRowsCollection?: AuditRow[]
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
  auditRowsCollection?: AuditRow[]
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
  auditRowsCollection?: AuditRow[];
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
  auditRowsCollection?: AuditRow[];
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
  auditRowsCollection?: AuditRow[];
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
  auditRowsCollection?: AuditRow[]
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
  auditRowsCollection?: AuditRow[];
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
  auditRowsCollection?: AuditRow[]
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
  const auditRowsCollection: AuditRow[] = [];
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

  await saveAuditRows(auditRowsCollection as AuditRow[]);

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

export const executeRawQuery = async (rawSql: string) => {
  const { sql, bindings } = parseSQLWithHints(rawSql);
  const auditRowsCollection: AuditRow[] = [];
  const rows = await executeQuery(sql, bindings, {
    auditRowsCollection,
  });
  await saveAuditRows(auditRowsCollection);
  const auditRowsCollectionWithOmittions = auditRowsCollection.map(
    (auditRow) => ({
      ...auditRow,
      sql: '<omitted>',
      bindings: [],
      stmtObject: '<omitted>',
    })
  );
  return {
    auditRows: auditRowsCollectionWithOmittions,
    rows,
  };
};
