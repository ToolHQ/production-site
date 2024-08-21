import { getConnection, ConnectionType } from '@dnorio/db-wrapper';

import { extractQueryMetadata } from './node-sql-parser.js';
import { computeElapsedTimeMsFromHrTimes } from './timer.js';

export const executeQuery = async (
  sql: string,
  connection: ConnectionType = 'postgres_default'
) => {
  const auditStartTime = process.hrtime();
  const auditRows = extractQueryMetadata(sql).statements.map((stmt) => ({
    stmt: stmt.stmt,
    stmtKind: stmt.stmtKind,
    stmtSyntax: stmt.stmtSyntax,
    stmtSubCommands: stmt.stmtSubCommands,
    stmtTarget: stmt.stmtTarget,
    stmtOptions: stmt.stmtOptions,
    sql: '<omitted>',
    stmtObject: '<omitted>',
  }));
  const auditElapsedTime = computeElapsedTimeMsFromHrTimes(
    process.hrtime(),
    auditStartTime
  );
  const db = getConnection(connection);
  const queryStartTime = process.hrtime();
  const { rows } = await db.raw(sql);
  const queryElapsedTime = computeElapsedTimeMsFromHrTimes(
    process.hrtime(),
    queryStartTime
  );
  return {
    auditElapsedTime,
    queryElapsedTime,
    auditRows,
    rows,
  };
};
