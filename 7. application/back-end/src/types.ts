import { Todo } from './models/todo';

// import { entities } from '@dnorio/models-toolhq';
// type knownEntities = keyof typeof entities;

export type Empty = Record<string, never>;

/**
 * Test router
 */

/**
 * @title Returns Database Metadata
 * @description Allows to explore configurations at databases by connection name.
 */
export interface DatabaseMetadataParams {
  /**
   * Database connection name. Allowed value is only 'postgres'.
   */
  connectionName: 'postgres';
}

/**
 * @title Generate Migration
 * @description Returns migration DDL
 */
export interface GenerateMigrationParams {
  /**
   * Entity name
   */
  entityName: 'rawRequest' | 'rawRequestPartition';
}

export type GenerateMigrationResponseBody = string;

/**
 * Todos router
 */

/**
 * @title Creates a todo item
 * @description Creates a todo item by text.
 */
export interface CreateTodoInputBody {
  /**
   * Todo text description for search
   */
  text: string;
}

/**
 * @description 201 - Created
 */
export interface CreateTodoResponseBody {
  /**
   * Todo text result
   */
  message: string;
  createdTodo: Todo;
}

/**
 * @title Get list of todos
 * @description Retrieve the todo list by text
 */
export interface GetTodosQuery {
  /**
   * Todo text description for search.
   */
  text?: string;
}

export type GetTodosResponseBody = {
  todos: {
    id: string;
    text: string;
  }[];
};
