import { Router } from 'express';
import { getQueryMetadata, initDatabase } from '../controllers/db-manager.js';
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
export default router;
