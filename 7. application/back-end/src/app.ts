import { Readable } from 'node:stream';
import Logger from '@dnorio/logger'
import HttpClient from '@dnorio/httpclient'
import express, { Request, Response, NextFunction } from 'express';

import todoRoutes from './routes/todo';

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
  logger.info('Hello World!');
  logger.infoDB({ name: 'John', age: 30 }, 'User created');
  logger.error('Error message');
  logger.errorEvent('Error 112', Error('new one'));

  const streamReturn = await httpClient.callHTTP({
    uri: 'https://jsonplaceholder.typicode.com/todos/1',
    stream: true
  });
  Readable.fromWeb(streamReturn.body!).pipe(res);
})

app.listen(port, () => {
  logger.infoEvent('Server started', { port });
});
