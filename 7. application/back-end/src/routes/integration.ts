import { Router } from 'express';

import { testHttp, testDatabase } from '../controllers/integration.js';
import { validateMiddleware } from '../services/validations.js';
export const router = Router();

router.get('/http', testHttp);

router.get(
  '/database/:connectionName/metadata',
  validateMiddleware('DatabaseConfigParams'),
  testDatabase
);

export default router;
