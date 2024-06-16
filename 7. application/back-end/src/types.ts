// import { rawRequest } from '@dnorio/models-toolhq';
import { Todo } from './models/todo';
export interface DatabaseConfigParams {
  connectionName: 'postgres';
  port?: number;
  isActive?: boolean;
  options?: string[];
}

export type CreateTodoParams = Record<string, never>;

export type Empty = Record<string, never>;

export type GetTodosResponseBody = { todos: { id: string; text: string }[] };

export type GetTodosQuery = {
  text?: string;
};
export interface CreateTodoInputBody {
  text: string;
}

export interface CreateTodoResponseBody {
  message: string;
  createdTodo: Todo;
}

export interface GenerateMigrationParams {
  entityName: string;
}
