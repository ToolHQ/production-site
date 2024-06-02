import { Readable } from 'node:stream';
import Logger from '@dnorio/logger'
import HttpClient from '@dnorio/httpclient'
import express, { Request, Response, NextFunction } from 'express';

import todoRoutes from './routes/todo.js';

const { logger } = Logger();
const httpClient = HttpClient();
const app = express();
const port = 3000;

app.use(express.json());
app.use('/todos', todoRoutes);

const healthCheck: express.RequestHandler<void> = (_, res, _2) => {
  res.status(200).json({ message: 'Hello World!' });
}

app.use('/health', healthCheck)

app.use((error: Error, _: Request, res: Response, _2: NextFunction): void => {
  res.status(500).json({ message: error.message });
})

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
      'x-ratelimit-reset'
    ]
  });
  Readable.fromWeb(streamReturn.body!).pipe(res);
})

app.listen(port, () => {
  logger.infoEvent('Server started', { port });
});
