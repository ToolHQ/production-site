import Logger from '@dnorio/logger'
import express, { Request, Response, NextFunction } from 'express';

import todoRoutes from './routes/todo';

const { logger } = Logger();
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

app.listen(port, () => {
  logger.infoEvent('Server started', { port });
});
