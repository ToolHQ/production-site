import { Router } from 'express';

import {
  testHttp,
  testDatabase,
  executeMigration,
} from '../controllers/integration.js';
import { validateMiddleware } from '../services/validations.js';
export const router = Router();

router.get('/http', testHttp);

router.get(
  '/database/:connectionName/metadata',
  validateMiddleware('DatabaseMetadataParams'),
  testDatabase
);

router.get(
  '/migration/:entityName',
  validateMiddleware('GenerateMigrationParams'),
  executeMigration
);

export default router;
