import { getConnection, ConnectionType } from '@dnorio/db-wrapper';

import { computeElapsedTimeMsFromHrTimes } from './timer.js';

import { extractQueryMetadata } from '../services/node-sql-parser.js';

import { ParsedSelectOptions } from '@dnorio/pg-query-binding';

import { ddlAuditLog } from '@dnorio/models-toolhq';
import { randomUUID } from 'crypto';

type AuditRow = {
  operationType: string;
  sql: string;
  bindings: string[];
  stmt: string; // PostgresStmt
  stmtKind: string;
  stmtSyntax: string;
  stmtSubCommands: string[];
  stmtTarget: string;
  stmtOptions: unknown;
  executionTime: Date;
  totalElapsedTime: number;
};

/**
 * Safely replaces PostgreSQL-style $1, $2 placeholders with ? placeholders
 * at the exact positions specified in the positions array.
 *
 * @param {string} sql - The SQL query containing $1, $2, etc. placeholders.
 * @param {number[]} paramsRefs - An array of character positions where each $ placeholder occurs.
 * @param {string[]} bindings - An array of bindings to replace the placeholders with.
 * @returns {{ transformedSql: string; bindingsPerPosition: string[] }} - The transformed SQL query and the bindings in the correct order.
 */
const replacePlaceholdersAtPositions = (
  sql: string,
  paramsRefs: { location: number; i: number }[],
  bindings: string[]
): { transformedSql: string; bindingsPerPosition: string[] } => {
  // Sort positions in descending order to avoid shifting issues when replacing
  const sortedParamsRefs = paramsRefs.sort((a, b) => b.location - a.location);

  let transformedSql = sql;
  const bindingsPerPosition: string[] = [];

  for (const parsedParam of sortedParamsRefs) {
    // Safely replace the exact placeholder at the position with ?
    transformedSql = `${transformedSql.slice(
      0,
      parsedParam.location
    )}?${transformedSql.slice(parsedParam.location + 2)}`;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    bindingsPerPosition.unshift(bindings[parsedParam.i - 1]!);
  }

  return {
    transformedSql,
    bindingsPerPosition,
  };
};

export const saveAuditRows = async (auditRows: AuditRow[]) => {
  const db = getConnection('postgres_dba', { logs: false });
  const submissionId = randomUUID();
  await db('dba_audit.tb_ddl_audit_log').insert(
    auditRows.map((auditRow) =>
      ddlAuditLog.mapToDbObject({
        operationType: 'SELECT',
        sql: auditRow.sql,
        // sqlBindings: auditRow.bindings,
        stmt: auditRow.stmt,
        stmtKind: auditRow.stmtKind,
        stmtSyntax: auditRow.stmtSyntax,
        stmtSubCommands: auditRow.stmtSubCommands,
        stmtTarget: auditRow.stmtTarget,
        stmtOptions: auditRow.stmtOptions,
        submissionId,
        executedBy: 'db-manager',
        executionTime: auditRow.executionTime,
        status: 'success',
        // errorMessage: null,
        // rowsAffected: 0,
        elapsedTime: auditRow.totalElapsedTime,
      })
    )
  );
};

/**
 * Executes the provided SQL query at the provided connection, returning the audit and query metadata and the query results.
 * Audit rows are added to the provided auditRowsCollection array or saved if not provided.
 */
export const executeQuery = async <T>(
  sql: string,
  bindings: string[],
  options: {
    connection?: ConnectionType;
    returnRawData?: boolean;
    auditRowsCollection?: unknown[];
  } = {
    connection: 'postgres_default',
    returnRawData: true,
  }
) => {
  // Set default values for options
  const { connection = 'postgres_default', returnRawData = true } = options;

  const auditStartTime = process.hrtime();
  const auditRows = extractQueryMetadata(sql).statements.map((stmt) => ({
    stmt: stmt.stmt,
    stmtKind: stmt.stmtKind,
    stmtSyntax: stmt.stmtSyntax,
    stmtSubCommands: stmt.stmtSubCommands,
    stmtTarget: stmt.stmtTarget,
    stmtOptions: stmt.stmtOptions,
    sql: returnRawData ? sql : '<omitted>',
    bindings: returnRawData ? bindings : [],
    stmtObject: returnRawData ? stmt.stmtObject : '<omitted>',
  }));
  const auditElapsedTime = computeElapsedTimeMsFromHrTimes(
    process.hrtime(),
    auditStartTime
  );
  const db = getConnection(connection);
  let finalSql = sql;
  let finalBindings: string[] = bindings;
  if (bindings.length) {
    let paramsRefs: { location: number; i: number }[] = auditRows.reduce(
      (pv, cv) => {
        if ((cv?.stmtOptions as ParsedSelectOptions)?.parsedRefs?.param) {
          return pv.concat(
            (cv.stmtOptions as ParsedSelectOptions).parsedRefs.param
          );
        }
        return pv;
      },
      [] as { location: number; i: number }[]
    );
    if (paramsRefs.length === 0) {
      paramsRefs = sql.split('').reduce((pv, cv, i) => {
        if (cv === '$') {
          pv.push({
            location: i,
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
            i: parseInt(sql[i + 1]!, 10),
          });
        }
        return pv;
      }, [] as { location: number; i: number }[]);
    }

    const { transformedSql, bindingsPerPosition } =
      replacePlaceholdersAtPositions(sql, paramsRefs, bindings);
    finalSql = transformedSql;
    finalBindings = bindingsPerPosition;
  }
  const queryStartTime = process.hrtime();
  const executionTime = new Date();
  const { rows } = bindings.length
    ? await db.raw(finalSql, finalBindings)
    : await db.raw(finalSql);
  const queryElapsedTime = computeElapsedTimeMsFromHrTimes(
    process.hrtime(),
    queryStartTime
  );
  const totalElapsedTime = computeElapsedTimeMsFromHrTimes(
    process.hrtime(),
    auditStartTime
  );
  const auditRowsWithExecutionTime = auditRows.map((row) => ({
    auditElapsedTime,
    queryElapsedTime,
    totalElapsedTime,
    executionTime,
    ...row,
  }));
  if (options.auditRowsCollection) {
    options.auditRowsCollection.push(...auditRowsWithExecutionTime);
  } else {
    await saveAuditRows(auditRowsWithExecutionTime as unknown as AuditRow[]);
  }
  return rows as T;
};
