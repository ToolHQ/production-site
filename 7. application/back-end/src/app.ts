import express, { Request, Response, NextFunction } from 'express';

import Logger from '@dnorio/logger';
import { logRequestsConstructor } from '@dnorio/logger/requestLoggerMiddleware';

import { router as todoRoutes } from './routes/todo.js';
import integrationRoutes from './routes/integration.js';

const { logger } = Logger();
const app = express();
const port = 3000;

app.use(express.json());

app.use('/test', integrationRoutes);
app.use('/todos', todoRoutes);

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const healthCheck: express.RequestHandler<void> = (_, res) => {
  res.status(200).json({ message: 'Hello World!' });
};

app.use('/health', healthCheck);

app.use(logRequestsConstructor({ routesToIgnore: [], logResponseBody: true }));

// eslint-disable-next-line @typescript-eslint/no-unused-vars
app.use((error: Error, _: Request, res: Response, _2: NextFunction): void => {
  res.status(500).json({ message: error.message });
});

app.listen(port, () => {
  logger.infoEvent('Server started', { port });
});
