import './apm.js';
import express, { Request, Response, NextFunction } from 'express';

import Logger from '@dnorio/logger';
import { logRequestsConstructor } from '@dnorio/logger/requestLoggerMiddleware';
import { setReqIdMiddleware } from '@dnorio/logger/setId';

import { router as todoRoutes } from './routes/todo.js';
import integrationRoutes from './routes/integration.js';
import dbManagerRouter from './routes/db-manager.js';
import { addSwaggerToExpress } from './services/swagger.js';
import { validateQueries } from './services/node-sql-parser.js';

const { logger } = Logger();

const app = express();
const port = 3000;

app.use(setReqIdMiddleware);
app.use(express.json());
app.use(
  logRequestsConstructor({
    routesToIgnore: ['/health'],
    logResponseBody: false,
  })
);

app.use('/test', integrationRoutes);
app.use('/todos', todoRoutes);
app.use('/db-manager', dbManagerRouter);

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const healthCheck: express.RequestHandler<void> = (_, res) => {
  res.status(200).json({ message: 'Hello World!' });
};

app.get('/health', healthCheck);

app.disable('x-powered-by');

addSwaggerToExpress(app);

// eslint-disable-next-line @typescript-eslint/no-unused-vars
app.use((error: Error & { status?: number; statusCode?: number }, req: Request, res: Response, _2: NextFunction): void => {
  const statusCode = error.status ?? error.statusCode ?? 500;
  logger.errorEvent('Server ERROR', {
    method: req.method,
    path: req.path,
    name: error.name,
    stack: error.stack,
    message: error.message,
    cause: error.cause,
    statusCode,
  });
  const isProduction = process.env.NODE_ENV === 'production';
  res.status(statusCode).json({
    message: isProduction && statusCode === 500 ? 'Internal Server Error' : error.message,
  });
});

app.listen(port, () => {
  logger.infoEvent('Server started', { port });
  validateQueries();
});
