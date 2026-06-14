import { RequestHandler } from 'express';

import { Todo } from '../models/todo.js';

import {
  CreateTodoResponseBody,
  CreateTodoInputBody,
  GetTodosResponseBody,
  GetTodosQuery,
  Empty,
} from '../types.js';

const TODOS: Todo[] = [];

export const createTodo: RequestHandler<
  Empty,
  CreateTodoResponseBody,
  CreateTodoInputBody
> = (req, res) => {
  const { text } = req.body;
  const newTodo = new Todo(Math.random().toString(), text);
  TODOS.push(newTodo);
  res.status(201).json({ message: 'Created the todo.', createdTodo: newTodo });
};

export const getTodos: RequestHandler<
  Empty,
  GetTodosResponseBody,
  Empty,
  GetTodosQuery
> = (req, res) => {
  const {
    query: { text },
  } = req;
  console.log(String(text ?? '').replace(/[\r\n]/g, ''));
  res.status(200).json({ todos: TODOS });
};

export const updateTodo: RequestHandler<{ id: string }> = (req, res) => {
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

export const deleteTodo: RequestHandler<{ id: string }> = (req, res) => {
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
