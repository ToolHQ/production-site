import { Router } from 'express';
import { initDatabase } from '../controllers/db-manager.js';
import { validateMiddleware } from '../services/validations.js';

const router = Router();

router.post(
  '/init/:connectionName',
  validateMiddleware('InitDatabaseParams', 'InitDatabaseBody'),
  initDatabase
);
export default router;
