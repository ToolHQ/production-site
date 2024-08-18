import { Router, text } from 'express';
import {
  getQueryMetadata,
  initDatabase,
  executeQueries,
} from '../controllers/db-manager.js';
import { validateMiddleware } from '../services/validations.js';

const router = Router();

router.post(
  '/init/:connectionName',
  validateMiddleware('InitDatabaseParams', 'InitDatabaseBody'),
  initDatabase
);

router.post(
  '/query/metadata',
  validateMiddleware(
    'Empty',
    'GetQueryMetadataBody',
    'Empty',
    'GetQueryMetadataResponseBody'
  ),
  getQueryMetadata
);

router.post(
  '/query/execute',
  text(),
  validateMiddleware(
    'Empty',
    'ExecuteQueriesPlainText',
    'Empty',
    'ExecuteQueriesResponseBody'
  ),
  executeQueries
);
export default router;
