import { RequestHandler } from 'express';

import { Todo } from '../models/todo';

const TODOS: Todo[] = [];

export const createTodo: RequestHandler = (req, res, _) => {
  const { text } = req.body as { text: string };
  const newTodo = new Todo(Math.random().toString(), text);
  TODOS.push(newTodo);
  res.status(201).json({ message: 'Created the todo.', createdTodo: newTodo });
};

export const getTodos: RequestHandler = (_, res, _2) => {
  res.status(200).json({ todos: TODOS });
};

export const updateTodo: RequestHandler<{ id: string }> = (req, res, _) => {
  const {
    params: { id },
  } = req;
  const { text: updatedText } = req.body as { text: string };
  const todoIndex = TODOS.findIndex((todo) => todo.id === id);
  if (todoIndex < 0) {
    throw Error('Could not find todo');
  }
  TODOS[todoIndex] = new Todo(id, updatedText);
  res
    .status(200)
    .json({ message: 'Updated the todo.', updatedTodo: TODOS[todoIndex] });
};

export const deleteTodo: RequestHandler<{ id: string }> = (req, res, _) => {
  const {
    params: { id },
  } = req;
  const todoIndex = TODOS.findIndex((todo) => todo.id === id);
  if (todoIndex < 0) {
    throw Error('Could not find todo');
  }
  TODOS.splice(todoIndex, 1);
  res.status(200).json({ message: 'Deleted the todo.' });
};
