import { RequestHandler } from 'express';

import {
  Empty,
  ExecuteQueriesPlainText,
  ExecuteQueriesResponseBody,
  GetQueryMetadataBody,
  GetQueryMetadataResponseBody,
  InitDatabaseBody,
  InitDatabaseParams,
} from '../types.js';

import {
  executeInitDatabase,
  executeGetQueryMetadata,
  executeQuery,
} from '../services/db-manager.js';

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

export const getQueryMetadata: RequestHandler<
  Empty,
  GetQueryMetadataResponseBody,
  GetQueryMetadataBody
> = (req, res, next) => {
  try {
    const result = executeGetQueryMetadata(
      req.body.query,
      req.body.omitStatementObject
    );
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
    const result = await executeQuery(sql);
    res.json(result);
  } catch (error) {
    next(error);
  }
};
