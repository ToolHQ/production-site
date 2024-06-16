import { Router } from 'express';

import {
  createTodo,
  getTodos,
  updateTodo,
  deleteTodo,
} from '../controllers/todos.js';

import { validateMiddleware } from '../services/validations.js';

export const router = Router();

router.post(
  '/',
  validateMiddleware('CreateTodoParams', 'CreateTodoInputBody'),
  createTodo
);

router.get('/', getTodos);

router.patch('/:id', updateTodo);

router.delete('/:id', deleteTodo);

export default router;
