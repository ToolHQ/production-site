import { Router } from 'express';

import { testHttp, testDatabase } from '../controllers/integration.js';

export const router = Router();

router.get('/http', testHttp);

router.get('/database/:connectionString/metadata', testDatabase);

export default router;
