import path, { dirname } from 'node:path';
import { Readable } from 'node:stream';
import { fileURLToPath } from 'node:url';

import { RequestHandler } from 'express';

import HttpClient from '@dnorio/httpclient';
import { getConnection } from '@dnorio/db-wrapper';

import { rawRequest, entities } from '@dnorio/models-toolhq';

import { generateDatabaseDDLFromModel } from '@dnorio/models-generator';

import { readFileAsync } from '../services/fs.js';
import {
  DatabaseMetadataParams,
  Empty,
  GenerateMigrationParams,
  GenerateMigrationResponseBody,
} from '../types.js';

const httpClient = HttpClient();

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const cwd = path.resolve(__dirname);

export const testHttp: RequestHandler = async (_req, res) => {
  const streamReturn = await httpClient.callHTTP({
    uri: 'https://jsonplaceholder.typicode.com/todos/1',
    stream: true,
    outputHeadersToHide: [
      'access-control-allow-credentials',
      'age',
      'alt-svc',
      'cache-control',
      'cf-cache-status',
      'cf-ray',
      'connection',
      'content-encoding',
      'content-type',
      'date',
      'etag',
      'expires',
      'nel',
      'pragma',
      'report-to',
      'reporting-endpoints',
      'server',
      'transfer-encoding',
      'vary',
      'via',
      'x-content-type-options',
      'x-powered-by',
      'x-ratelimit-limit',
      'x-ratelimit-remaining',
      'x-ratelimit-reset',
    ],
  });
  res.setHeader('Content-Type', 'application/json');
  if (streamReturn.body) {
    Readable.fromWeb(streamReturn.body).pipe(res);
  } else {
    res.end();
  }
};

type ColumnMetadata = {
  position: number;
  name: string;
  defaultValue: unknown | null;
  nullable: boolean;
  type: string;
  dataType: string;
  maxChars: number | null;
  maxBytes: number | null;
  numericPrecision: unknown;
  numericRadix: unknown;
  numericScale: unknown;
  dateTimePrecision: unknown;
  collationCatalog: string | null;
  collationSchema: string | null;
  collationName: string | null;
};
type DatabaseMetadata<T = ColumnMetadata> = {
  catalog: string;
  schema: string;
  name: string;
  type: 'BASE TABLE' | 'VIEW';
  columns: T[];
  constraints: {
    name: string;
    type: 'UNIQUE' | 'PRIMARY KEY' | 'CHECK';
    clause: string | null;
    columns: string[];
  }[];
};

interface RawDatabaseQueryReturn {
  rows: DatabaseMetadata<
    Omit<ColumnMetadata, 'nullable'> & { nullable: string }
  >[];
  name: string;
  date_created: Date;
}

const getDatabaseMetadata = async (
  connectionName: 'postgres'
): Promise<DatabaseMetadata<ColumnMetadata>[]> => {
  const sql = (
    await readFileAsync({
      filePath: path.join(cwd, '../../resources/sql/db_metadata.sql'),
    })
  )
    .toString()
    .trim();
  const db = getConnection(connectionName);
  const result = await db.raw<RawDatabaseQueryReturn>(sql);
  return result.rows.map(({ columns, ...otherProperties }) => ({
    ...otherProperties,
    columns: columns.map(({ nullable, ...otherColumns }) => ({
      nullable: nullable === 'YES',
      ...otherColumns,
    })),
  }));
};

export const testDatabase: RequestHandler<DatabaseMetadataParams> = async (
  req,
  res,
  next
) => {
  try {
    const {
      params: { connectionName },
    } = req;
    res.json({
      total: Object.keys(await getDatabaseMetadata(connectionName)).length,
      entityData: {
        tableName: rawRequest.tableName,
      },
    });
  } catch (error) {
    next(error);
  }
};

export const executeMigration: RequestHandler<
  GenerateMigrationParams,
  GenerateMigrationResponseBody,
  Empty,
  Empty
> = async (req, res, next) => {
  try {
    const {
      params: { entityName },
    } = req;
    const ddl = generateDatabaseDDLFromModel({
      entity: entities[entityName as keyof typeof entities],
      options: {
        ifNotExists: false,
        generationOptions: {},
      },
    });
    res.set('Content-Type', 'text/plain');
    res.send(ddl);
  } catch (error) {
    next(error);
  }
};
