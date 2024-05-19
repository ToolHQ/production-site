import express, { Request, Response, NextFunction } from 'express';

import todoRoutes from './routes/todo';

const app = express();
const port = 3000;

app.use(express.json());
app.use('/todos', todoRoutes);

app.use((error: Error, _: Request, res: Response, _2: NextFunction): void => {
  res.status(500).json({ message: error.message });
})

app.listen(port, () => {
  console.log(`Server is running on port ${port}`);
});
