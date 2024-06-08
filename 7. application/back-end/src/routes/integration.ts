import { RequestHandler, Router } from 'express';

import { testHttp, testDatabase } from '../controllers/integration.js';
import { validateMiddleware } from '../services/validations.js';
import { DatabaseConfigParams } from '../types.js';

export const router = Router();

router.get('/http', testHttp);

router.get(
  '/database/:connectionName/metadata',
  validateMiddleware(
    'DatabaseConfigParams'
  ) as unknown as RequestHandler<DatabaseConfigParams>,
  testDatabase
);

export default router;
