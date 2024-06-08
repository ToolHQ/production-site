import { Router } from 'express';

import { testHttp } from '../controllers/integration.js';

export const router = Router();

router.get('/http', testHttp);

export default router;
