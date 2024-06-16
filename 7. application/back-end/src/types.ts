// import { rawRequest } from '@dnorio/models-toolhq';
import { Todo } from './models/todo';

/**
 * Allows to explore configurations at database by connectionName
 */
export interface DatabaseConfigParams {
  /**
   * db-wrapper connection name
   */
  connectionName: 'postgres';
}

export type CreateTodoParams = Record<string, never>;

export type Empty = Record<string, never>;

export type GetTodosResponseBody = { todos: { id: string; text: string }[] };

export interface GetTodosQuery {
  /**
   * Todo text description for search
   * @TJS-type string
   */
  text?: string;
}
export interface CreateTodoInputBody {
  /**
   * Todo text description for search
   * @TJS-type string
   */
  text: string;
}

export interface CreateTodoResponseBody {
  /**
   * Todo text result
   * @TJS-type string
   */
  message: string;
  createdTodo: Todo;
}

export interface GenerateMigrationParams {
  /**
   * Entity name
   * @TJS-type string
   */
  entityName: string;
}
