// import { PostgresStmts } from '@dnorio/pg-query-binding';

import { Todo } from './models/todo';

// import { entities } from '@dnorio/models-toolhq';
// type knownEntities = keyof typeof entities;

export type Empty = Record<string, never>;

/**
 * Database Manager Router
 *
 */

/**
 * @title Inits manager database
 * @description Inits a dba database at the instance by connection name. Inits tables for auditing and automate execution of DDLs.
 */
export type InitDatabaseParams = {
  connectionName: 'postgres' | 'oracledb' | 'redshift' | 'mssql';
};

export type InitDatabaseBody = {
  /**
   * @default null
   */
  schema?: string;
  /**
   * @default null
   */
  database?: string;
  /**
   * @default false
   */
  reset?: boolean;
};

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
  entityName:
    | 'rawRequest'
    | 'rawRequestPartition'
    | 'ddlAuditLog'
    | 'ddlAuditLogPartition';
}

export type GenerateMigrationResponseBody = string;

export type GetQueryMetadataBody = {
  query: string;
  /**
   * @default false
   */
  omitStatementObject?: boolean;
};

export type GetQueryMetadataResponseBody = {
  version: number | null;
  statements: {
    stmtKind?: string | null | undefined;
    stmtSyntax?: string | null | undefined;
    stmtSubCommands?: string[] | null | undefined;
    stmt: string;
    stmtObject?: unknown;
  }[];
};

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
  todos: Todo[];
};
