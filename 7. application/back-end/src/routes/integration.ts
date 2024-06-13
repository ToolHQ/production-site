import { Router } from 'express';

import {
  testHttp,
  testDatabase,
  executeMigration,
} from '../controllers/integration.js';
import { validateMiddleware } from '../services/validations.js';
export const router = Router();

router.all('/http', testHttp);

router.propfind(
  '/database/:connectionName/metadata',
  validateMiddleware('DatabaseConfigParams'),
  testDatabase
);

router.get(
  '/migration/:entityName',
  validateMiddleware('GenerateMigrationParams'),
  executeMigration
);

export default router;
