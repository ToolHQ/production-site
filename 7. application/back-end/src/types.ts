// import { rawRequest } from '@dnorio/models-toolhq';
import { Todo } from './models/todo';
export interface DatabaseConfigParams {
  connectionName: 'postgres';
  port?: number;
  isActive?: boolean;
  options?: string[];
}

export type CreateTodoParams = Record<string, never>;
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
