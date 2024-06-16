import express, { Request, Response, NextFunction } from 'express';

import Logger from '@dnorio/logger';
import { logRequestsConstructor } from '@dnorio/logger/requestLoggerMiddleware';
import { setReqIdMiddleware } from '@dnorio/logger/setId';

import { router as todoRoutes } from './routes/todo.js';
import integrationRoutes from './routes/integration.js';
import { addSwaggerToExpress } from './services/swagger.js';

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

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const healthCheck: express.RequestHandler<void> = (_, res) => {
  res.status(200).json({ message: 'Hello World!' });
};

app.get('/health', healthCheck);

// comments.js
const commentsRoutes = express.Router({ mergeParams: false });
commentsRoutes.get('/', (req, res) => {
  console.log(req.params);
  res.json(req.params);
});

app.use('/:id/comments', commentsRoutes);

addSwaggerToExpress(app);

// eslint-disable-next-line @typescript-eslint/no-unused-vars
app.use((error: Error, req: Request, res: Response, _2: NextFunction): void => {
  logger.errorEvent('Server ERROR', {
    method: req.method,
    path: req.path,
    name: error.name,
    stack: error.stack,
    message: error.message,
    cause: error.cause,
  });
  res.status(500).json({ message: error.message });
});

app.listen(port, () => {
  logger.infoEvent('Server started', { port });
});
