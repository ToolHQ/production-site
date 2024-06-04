import { Readable } from 'node:stream';

import express, { Request, Response, NextFunction } from 'express';

import Logger from '@dnorio/logger';
import { logRequestsConstructor } from '@dnorio/logger/requestLoggerMiddleware';
import HttpClient from '@dnorio/httpclient';

import todoRoutes from './routes/todo.js';

const { logger } = Logger();
const httpClient = HttpClient();
const app = express();
const port = 3000;

app.use(express.json());
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

app.use('/test', async (_, res) => {
  const streamReturn = await httpClient.callHTTP({
    uri: 'https://jsonplaceholder.typicode.com/todos/1',
    stream: true,
    outputHeadersToHide: [
      'access-control-allow-credentials',
      'age',
      'alt-svc',
      'cache-control',
      'cf-cache-status',
      'cf-ray',
      'connection',
      'content-encoding',
      'content-type',
      'date',
      'etag',
      'expires',
      'nel',
      'pragma',
      'report-to',
      'reporting-endpoints',
      'server',
      'transfer-encoding',
      'vary',
      'via',
      'x-content-type-options',
      'x-powered-by',
      'x-ratelimit-limit',
      'x-ratelimit-remaining',
      'x-ratelimit-reset',
    ],
  });
  if (streamReturn.body) {
    Readable.fromWeb(streamReturn.body).pipe(res);
  } else {
    res.end();
  }
});

app.listen(port, () => {
  logger.infoEvent('Server started', { port });
});
