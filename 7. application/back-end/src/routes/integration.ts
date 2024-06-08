import { Router } from 'express';

import { testHttp } from '../controllers/integration.js';

export const router = Router();

router.post('/http', testHttp);

export default router;
