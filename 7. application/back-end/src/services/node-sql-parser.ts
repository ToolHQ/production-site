/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { parseQueryDetailed } from '@dnorio/pg-query-binding';
import Logger from '@dnorio/logger';

import {
  DDLStatements,
  statementTypeCount,
  statementTypeQueries,
  queries,
} from './test-queries-data.js';

const { logger } = Logger();

export const extractQueryMetadata = (query: string) => {
  try {
    return parseQueryDetailed(query);
  } catch (error: unknown) {
    const err = error as Error & {
      funcname: string;
      filename: string;
      lineno: number;
      cursorpos: number;
    };
    logger.errorEvent('queryParseError', {
      query,
      message: err.message,
      funcname: err.funcname,
      filename: err.filename,
      lineno: err.lineno,
      cursorpos: err.cursorpos,
    });
    throw err;
  }
};

const missingQueriesForTest = DDLStatements.filter(
  (statement) =>
    !queries.some((query) => query.name === statement && query.query)
);
if (missingQueriesForTest.length > 0) {
  logger.infoEvent('missingQueriesForTest', missingQueriesForTest);
}

export const validateQueries = () => {
  for (const query of queries) {
    try {
      const parsed = parseQueryDetailed(query.query);
      for (const parsedStatement of parsed.statements) {
        const statementType = `${parsedStatement.stmt}/${
          parsedStatement.stmtKind
        }/${parsedStatement.stmtSyntax}/${parsedStatement.stmtSubCommands?.join(
          ','
        )}`;
        if (!statementTypeCount.has(statementType)) {
          statementTypeCount.set(statementType, 1);
          statementTypeQueries.set(statementType, [
            { query: query.name, parsed },
          ]);
        } else {
          statementTypeCount.set(
            statementType,
            statementTypeCount.get(statementType)! + 1
          );
          statementTypeQueries.set(
            statementType,
            statementTypeQueries
              .get(statementType)!
              .concat({ query: query.name, parsed })
          );
        }
      }
      // console.log(`${query.name}: ${statementType}`);
    } catch (error: unknown) {
      const err = error as Error & {
        funcname: string;
        filename: string;
        lineno: number;
        cursorpos: number;
      };
      logger.errorEvent('queryParseError', {
        query: query.name,
        message: err.message,
        funcname: err.funcname,
        filename: err.filename,
        lineno: err.lineno,
        cursorpos: err.cursorpos,
      });
      throw err;
    }
  }
  for (const [statementType, count] of statementTypeCount) {
    if (count > 1) {
      const queries = statementTypeQueries.get(statementType)!;
      type NewType = {
        query: string;
      };
      logger.infoEvent(
        'Ambigous statementTypeCount',
        statementType,
        queries.map((q) => {
          // if (index === 0 || index === 1 || index === 2) {
          // console.log(
          //   `${(q as { query: string }).query}: ${statementType}`,
          //   JSON.stringify((q as { parsed: unknown }).parsed, null, 2)
          // );
          // }
          return (q as NewType).query;
        })
      );
    }
  }
  // logger.infoEvent('types', [...statementTypeCount.entries()]);
};
