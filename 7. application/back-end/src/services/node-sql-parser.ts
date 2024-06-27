/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { parseQuery } from '@dnorio/pg-query-binding';
import Logger from '@dnorio/logger';

const { logger } = Logger();

// https://www.postgresql.org/docs/current/sql-commands.html
const DDLStatements = [
  'ABORT', // abort the current transaction
  'ALTER AGGREGATE', // change the definition of an aggregate function
  'ALTER COLLATION', // change the definition of a collation
  'ALTER CONVERSION', // change the definition of a conversion
  'ALTER DATABASE', // change a database
  'ALTER DEFAULT PRIVILEGES', // define default access privileges
  'ALTER DOMAIN', // change the definition of a domain
  'ALTER EVENT TRIGGER', // change the definition of an event trigger
  'ALTER EXTENSION', // change the definition of an extension
  'ALTER FOREIGN DATA WRAPPER', // change the definition of a foreign-data wrapper
  'ALTER FOREIGN TABLE', // change the definition of a foreign table
  'ALTER FUNCTION', // change the definition of a function
  'ALTER GROUP', // change role name or membership
  'ALTER INDEX', // change the definition of an index
  'ALTER LANGUAGE', // change the definition of a procedural language
  'ALTER LARGE OBJECT', // change the definition of a large object
  'ALTER MATERIALIZED VIEW', // change the definition of a materialized view
  'ALTER OPERATOR', // change the definition of an operator
  'ALTER OPERATOR CLASS', // change the definition of an operator class
  'ALTER OPERATOR FAMILY', // change the definition of an operator family
  'ALTER POLICY', // change the definition of a row-level security policy
  'ALTER PROCEDURE', // change the definition of a procedure
  'ALTER PUBLICATION', // change the definition of a publication
  'ALTER ROLE', // change a database role
  'ALTER ROUTINE', // change the definition of a routine
  'ALTER RULE', // change the definition of a rule
  'ALTER SCHEMA', // change the definition of a schema
  'ALTER SEQUENCE', // change the definition of a sequence generator
  'ALTER SERVER', // change the definition of a foreign server
  'ALTER STATISTICS', // change the definition of an extended statistics object
  'ALTER SUBSCRIPTION', // change the definition of a subscription
  'ALTER SYSTEM', // change a server configuration parameter
  'ALTER TABLE', // change the definition of a table
  'ALTER TABLESPACE', // change the definition of a tablespace
  'ALTER TEXT SEARCH CONFIGURATION', // change the definition of a text search configuration
  'ALTER TEXT SEARCH DICTIONARY', // change the definition of a text search dictionary
  'ALTER TEXT SEARCH PARSER', // change the definition of a text search parser
  'ALTER TEXT SEARCH TEMPLATE', // change the definition of a text search template
  'ALTER TRIGGER', // change the definition of a trigger
  'ALTER TYPE', // change the definition of a type
  'ALTER USER', // change a database role
  'ALTER USER MAPPING', // change the definition of a user mapping
  'ALTER VIEW', // change the definition of a view
  'ANALYZE', // collect statistics about a database
  'BEGIN', // start a transaction block
  'CALL', // invoke a procedure
  'CHECKPOINT', // force a write-ahead log checkpoint
  'CLOSE', // close a cursor
  'CLUSTER', // cluster a table according to an index
  'COMMENT', // define or change the comment of an object
  'COMMIT', // commit the current transaction
  'COMMIT PREPARED', // commit a transaction that was earlier prepared for two-phase commit
  'COPY', // copy data between a file and a table
  'CREATE ACCESS METHOD', // define a new access method
  'CREATE AGGREGATE', // define a new aggregate function
  'CREATE CAST', // define a new cast
  'CREATE COLLATION', // define a new collation
  'CREATE CONVERSION', // define a new encoding conversion
  'CREATE DATABASE', // create a new database
  'CREATE DOMAIN', // define a new domain
  'CREATE EVENT TRIGGER', // define a new event trigger
  'CREATE EXTENSION', // install an extension
  'CREATE FOREIGN DATA WRAPPER', // define a new foreign-data wrapper
  'CREATE FOREIGN TABLE', // define a new foreign table
  'CREATE FUNCTION', // define a new function
  'CREATE GROUP', // define a new database role
  'CREATE INDEX', // define a new index
  'CREATE LANGUAGE', // define a new procedural language
  'CREATE MATERIALIZED VIEW', // define a new materialized view
  'CREATE OPERATOR', // define a new operator
  'CREATE OPERATOR CLASS', // define a new operator class
  'CREATE OPERATOR FAMILY', // define a new operator family
  'CREATE POLICY', // define a new row-level security policy for a table
  'CREATE PROCEDURE', // define a new procedure
  'CREATE PUBLICATION', // define a new publication
  'CREATE ROLE', // define a new database role
  'CREATE RULE', // define a new rewrite rule
  'CREATE SCHEMA', // define a new schema
  'CREATE SEQUENCE', // define a new sequence generator
  'CREATE SERVER', // define a new foreign server
  'CREATE STATISTICS', // define extended statistics
  'CREATE SUBSCRIPTION', // define a new subscription
  'CREATE TABLE', // define a new table
  'CREATE TABLE AS', // define a new table from the results of a query
  'CREATE TABLESPACE', // define a new tablespace
  'CREATE TEXT SEARCH CONFIGURATION', // define a new text search configuration
  'CREATE TEXT SEARCH DICTIONARY', // define a new text search dictionary
  'CREATE TEXT SEARCH PARSER', // define a new text search parser
  'CREATE TEXT SEARCH TEMPLATE', // define a new text search template
  'CREATE TRANSFORM', // define a new transform
  'CREATE TRIGGER', // define a new trigger
  'CREATE TYPE', // define a new data type
  'CREATE USER', // define a new database role
  'CREATE USER MAPPING', // define a new mapping of a user to a foreign server
  'CREATE VIEW', // define a new view
  'DEALLOCATE', // deallocate a prepared statement
  'DECLARE', // define a cursor
  'DELETE', // delete rows of a table
  'DISCARD', // discard session state
  'DO', // execute an anonymous code block
  'DROP ACCESS METHOD', // remove an access method
  'DROP AGGREGATE', // remove an aggregate function
  'DROP CAST', // remove a cast
  'DROP COLLATION', // remove a collation
  'DROP CONVERSION', // remove a conversion
  'DROP DATABASE', // remove a database
  'DROP DOMAIN', // remove a domain
  'DROP EVENT TRIGGER', // remove an event trigger
  'DROP EXTENSION', // remove an extension
  'DROP FOREIGN DATA WRAPPER', // remove a foreign-data wrapper
  'DROP FOREIGN TABLE', // remove a foreign table
  'DROP FUNCTION', // remove a function
  'DROP GROUP', // remove a database role
  'DROP INDEX', // remove an index
  'DROP LANGUAGE', // remove a procedural language
  'DROP MATERIALIZED VIEW', // remove a materialized view
  'DROP OPERATOR', // remove an operator
  'DROP OPERATOR CLASS', // remove an operator class
  'DROP OPERATOR FAMILY', // remove an operator family
  'DROP OWNED', // remove database objects owned by a database role
  'DROP POLICY', // remove a row-level security policy from a table
  'DROP PROCEDURE', // remove a procedure
  'DROP PUBLICATION', // remove a publication
  'DROP ROLE', // remove a database role
  'DROP ROUTINE', // remove a routine
  'DROP RULE', // remove a rewrite rule
  'DROP SCHEMA', // remove a schema
  'DROP SEQUENCE', // remove a sequence
  'DROP SERVER', // remove a foreign server descriptor
  'DROP STATISTICS', // remove extended statistics
  'DROP SUBSCRIPTION', // remove a subscription
  'DROP TABLE', // remove a table
  'DROP TABLESPACE', // remove a tablespace
  'DROP TEXT SEARCH CONFIGURATION', // remove a text search configuration
  'DROP TEXT SEARCH DICTIONARY', // remove a text search dictionary
  'DROP TEXT SEARCH PARSER', // remove a text search parser
  'DROP TEXT SEARCH TEMPLATE', // remove a text search template
  'DROP TRANSFORM', // remove a transform
  'DROP TRIGGER', // remove a trigger
  'DROP TYPE', // remove a data type
  'DROP USER', // remove a database role
  'DROP USER MAPPING', // remove a user mapping for a foreign server
  'DROP VIEW', // remove a view
  'END', // commit the current transaction
  'EXECUTE', // execute a prepared statement
  'EXPLAIN', // show the execution plan of a statement
  'FETCH', // retrieve rows from a query using a cursor
  'GRANT', // define access privileges
  'IMPORT FOREIGN SCHEMA', // import table definitions from a foreign server
  'INSERT', // create new rows in a table
  'LISTEN', // listen for a notification
  'LOAD', // load a shared library file
  'LOCK', // lock a table
  'MERGE', // conditionally insert, update, or delete rows of a table
  'MOVE', // position a cursor
  'NOTIFY', // generate a notification
  'PREPARE', // prepare a statement for execution
  'PREPARE TRANSACTION', // prepare the current transaction for two-phase commit
  'REASSIGN OWNED', // change the ownership of database objects owned by a database role
  'REFRESH MATERIALIZED VIEW', // replace the contents of a materialized view
  'REINDEX', // rebuild indexes
  'RELEASE', // release a previously defined savepoint
  'RESET', // restore the value of a run-time parameter to the default value
  'REVOKE', // remove access privileges
  'ROLLBACK', // abort the current transaction
  'ROLLBACK PREPARED', // cancel a transaction that was earlier prepared for two-phase commit
  'ROLLBACK TO SAVEPOINT', // roll back to a savepoint
  'SAVEPOINT', // define a new savepoint within the current transaction
  'SECURITY LABEL', // define or change a security label applied to an object
  'SELECT', // retrieve rows from a table or view
  'SELECT INTO', // define a new table from the results of a query
  'SET', // change a run-time parameter
  'SET CONSTRAINTS', // set constraint check timing for the current transaction
  'SET ROLE', // set the current user identifier of the current session
  'SET SESSION AUTHORIZATION', // set the session user identifier and the current user identifier of the current session
  'SET TRANSACTION', // set the characteristics of the current transaction
  'SHOW', // show the value of a run-time parameter
  'START TRANSACTION', // start a transaction block
  'TRUNCATE', // empty a table or set of tables
  'UNLISTEN', // stop listening for a notification
  'UPDATE', // update rows of a table
  'VACUUM', // garbage-collect and optionally analyze a database
  'VACUUM FULL', // Reclaim storage and optionally reorders rows (????????)
  'VACUUM FREEZE', // Reclaim storage and mark all tuples as frozen (????????)
  'VACUUM ANALYZE', // Reclaim storage and update statistics (????????)
  'VACUUM VERBOSE', // Reclaim storage and display progress information (????????)
  'VALUES', // compute a set of rows
];

const queries: { name: string; description: string; query: string }[] = [
  {
    name: 'ABORT',
    description: 'Abort the current transaction',
    query: 'ABORT;',
  },
  {
    name: 'ALTER AGGREGATE',
    description: 'Change the definition of an aggregate function',
    query: `ALTER AGGREGATE calc_average(integer) SET SCHEMA public;`,
  },
  {
    name: 'ALTER COLLATION',
    description: 'Change the definition of a collation',
    query: 'ALTER COLLATION mycollation RENAME TO mycollation_new;',
  },
  {
    name: 'ALTER CONVERSION',
    description: 'Change the definition of a conversion',
    query: 'ALTER CONVERSION utf8_to_latin1 SET SCHEMA public;',
  },
  {
    name: 'ALTER DATABASE',
    description: 'Change a database',
    query: 'ALTER DATABASE mydb OWNER TO new_owner;',
  },
  {
    name: 'ALTER DEFAULT PRIVILEGES',
    description: 'Define default access privileges',
    query: `ALTER DEFAULT PRIVILEGES FOR ROLE my_role
GRANT SELECT ON TABLES TO PUBLIC;`,
  },
  {
    name: 'ALTER DOMAIN',
    description: 'Change the definition of a domain',
    query: "ALTER DOMAIN my_domain SET DEFAULT 'unknown';",
  },
  {
    name: 'ALTER EVENT TRIGGER',
    description: 'Change the definition of an event trigger',
    query: 'ALTER EVENT TRIGGER audit_log DISABLE;',
  },
  {
    name: 'ALTER EXTENSION',
    description: 'Change the definition of an extension',
    query: "ALTER EXTENSION hstore UPDATE TO '1.6.2';",
  },
  {
    name: 'ALTER FOREIGN DATA WRAPPER',
    description: 'Change the definition of a foreign-data wrapper',
    query:
      "ALTER FOREIGN DATA WRAPPER postgres_fdw OPTIONS (SET fetch_size '100');",
  },
  {
    name: 'ALTER FOREIGN TABLE',
    description: 'Change the definition of a foreign table',
    query:
      "ALTER FOREIGN TABLE my_foreign_table OPTIONS (ADD fwd_option 'some_value');",
  },
  {
    name: 'ALTER FUNCTION',
    description: 'Change the properties of an existing function',
    query: 'ALTER FUNCTION my_function(integer) RENAME TO new_function_name;',
  },
  {
    name: 'ALTER GROUP',
    description: 'Modify an existing database group',
    query: 'ALTER GROUP my_group ADD USER new_user;',
  },
  {
    name: 'ALTER INDEX',
    description: 'Change the properties of an existing index',
    query: 'ALTER INDEX my_index RENAME TO new_index_name;',
  },
  {
    name: 'ALTER LANGUAGE',
    description: 'change the definition of a procedural language',
    query: 'ALTER LANGUAGE plpythonu RENAME TO plpython3u;',
  },
  {
    name: 'ALTER LARGE OBJECT',
    description: 'Change the definition of a large object',
    query: 'ALTER LARGE OBJECT 12345 OWNER TO new_owner;',
  },
  {
    name: 'ALTER MATERIALIZED VIEW',
    description: 'Change the definition of a materialized view',
    query: 'ALTER MATERIALIZED VIEW my_matview SET WITHOUT CLUSTER;',
  },
  {
    name: 'ALTER OPERATOR',
    description: 'Change the definition of an operator',
    query:
      'ALTER OPERATOR ^ (integer, integer) SET (RESTRICT = my_restrict_function);',
  },
  {
    name: 'ALTER OPERATOR CLASS',
    description: 'Change the definition of an operator class',
    query: 'ALTER OPERATOR CLASS my_op_class USING btree OWNER TO new_owner;',
  },
  {
    name: 'ALTER OPERATOR FAMILY',
    description: 'Change the definition of an operator family',
    query: 'ALTER OPERATOR FAMILY my_op_family USING btree OWNER TO new_owner;',
  },
  {
    name: 'ALTER POLICY',
    description: 'Change the definition of a row-level security policy',
    query: 'ALTER TABLE employees ENABLE ROW LEVEL SECURITY;',
  },
  {
    name: 'ALTER PROCEDURE',
    description: 'Change the definition of a procedure',
    query: 'ALTER PROCEDURE my_proc RENAME TO my_proc_new;',
  },
  {
    name: 'ALTER PUBLICATION',
    description: 'Change the definition of a publication',
    query: 'ALTER PUBLICATION my_pub ADD TABLE my_table;',
  },
  {
    name: 'ALTER ROLE',
    description: 'Change a database role',
    query: 'ALTER ROLE my_role RENAME TO my_role_new;',
  },
  {
    name: 'ALTER ROUTINE',
    description: 'Change the definition of a routine (function or procedure)',
    query: 'ALTER ROUTINE my_function OWNER TO new_owner;',
  },
  {
    name: 'ALTER RULE',
    description: 'Change the definition of a rule',
    query: 'ALTER TABLE my_table DISABLE RULE my_rule;',
  },
  {
    name: 'ALTER SCHEMA',
    description: 'Change the definition of a schema',
    query: 'ALTER SCHEMA my_schema RENAME TO my_schema_new;',
  },
  {
    name: 'ALTER SEQUENCE',
    description: 'Change the definition of a sequence generator',
    query: 'ALTER SEQUENCE my_seq RESTART WITH 100;',
  },
  {
    name: 'ALTER SERVER',
    description: 'Change the definition of a foreign server',
    query: "ALTER SERVER my_server OPTIONS (SET host 'new_host');",
  },
  {
    name: 'ALTER STATISTICS',
    description: 'Change the definition of an extended statistics',
    query: 'ALTER STATISTICS my_stats OWNER TO new_owner;',
  },
  {
    name: 'ALTER SUBSCRIPTION',
    description: 'Change the definition of a subscription',
    query: "ALTER SUBSCRIPTION my_sub SET (refresh_interval = '1 minute');",
  },
  {
    name: 'ALTER SYSTEM',
    description: 'Change a server configuration parameter',
    query: "ALTER SYSTEM SET shared_buffers = '8GB';",
  },
  {
    name: 'ALTER TABLE',
    description: 'Change the definition of a table',
    query: 'ALTER TABLE my_table ADD COLUMN new_column VARCHAR(50);',
  },
  {
    name: 'ALTER TABLESPACE',
    description: 'Change the definition of a tablespace',
    query: 'ALTER TABLESPACE my_tablespace RENAME TO new_tablespace_name;',
  },
  {
    name: 'ALTER TEXT SEARCH CONFIGURATION',
    description: 'Change the definition of a text search configuration',
    query:
      'ALTER TEXT SEARCH CONFIGURATION english ALTER MAPPING FOR asciiword, asciihword WITH english_stem;',
  },
  {
    name: 'ALTER TEXT SEARCH DICTIONARY',
    description: 'Change the definition of a text search dictionary',
    query: 'ALTER TEXT SEARCH DICTIONARY my_dict ( StopWords = newrussian );',
  },
  {
    name: 'ALTER TEXT SEARCH PARSER',
    description: 'Change the definition of a text search parser',
    query: 'ALTER TEXT SEARCH PARSER my_parser RENAME TO my_parser_new;',
  },
  {
    name: 'ALTER TEXT SEARCH TEMPLATE',
    description: 'Change the definition of a text search template',
    query: 'ALTER TEXT SEARCH TEMPLATE my_template RENAME TO my_template_new;',
  },
  {
    name: 'ALTER TRIGGER',
    description: 'Change the definition of a trigger',
    query: 'ALTER TRIGGER my_trigger ON my_table RENAME TO my_trigger_new;',
  },
  {
    name: 'ALTER TYPE',
    description: 'Change the definition of a type',
    query: 'ALTER TYPE my_type ADD ATTRIBUTE my_attr varchar;',
  },
  {
    name: 'ALTER USER',
    description: 'Change a database role',
    query: "ALTER USER my_user WITH PASSWORD 'new_password';",
  },
  {
    name: 'ALTER USER MAPPING',
    description: 'Change the definition of a user mapping for a foreign server',
    query:
      "ALTER USER MAPPING FOR my_user SERVER my_server OPTIONS (SET dbname 'mydb');",
  },
  {
    name: 'ALTER VIEW',
    description: 'Change the definition of a view',
    query: 'ALTER VIEW my_view RENAME COLUMN old_col TO new_col;',
  },
  {
    name: 'ANALYZE',
    description: 'Collect statistics about a database',
    query: 'ANALYZE VERBOSE my_table;',
  },
  {
    name: 'BEGIN',
    description: 'Start a transaction block',
    query: 'BEGIN;',
  },
  {
    name: 'CALL',
    description: 'Invoke a procedure',
    query: 'CALL my_procedure();',
  },
  {
    name: 'CHECKPOINT',
    description: 'Force a write-ahead log checkpoint',
    query: 'CHECKPOINT;',
  },
  {
    name: 'CLOSE',
    description: 'Close a cursor',
    query: 'CLOSE my_cursor;',
  },
  {
    name: 'CLUSTER',
    description: 'Cluster a table according to an index',
    query: 'CLUSTER my_table USING idx_column;',
  },
  {
    name: 'COMMENT',
    description: 'Define or change the comment of an object',
    query: "COMMENT ON TABLE my_table IS 'This is my table';",
  },
  {
    name: 'COMMIT',
    description: 'Commit the current transaction',
    query: 'COMMIT;',
  },
  {
    name: 'COMMIT PREPARED',
    description:
      'Commit a transaction that was earlier prepared for two-phase commit',
    query: "COMMIT PREPARED 'my_prepared_txn';",
  },
  {
    name: 'COPY',
    description: 'Copy data between a file and a table',
    query: "COPY my_table FROM '/path/to/file.csv' WITH (FORMAT CSV);",
  },
  {
    name: 'CREATE ACCESS METHOD',
    description: 'Define a new access method',
    query:
      'CREATE ACCESS METHOD my_method TYPE TABLE HANDLER handler_function;',
  },
  {
    name: 'CREATE AGGREGATE',
    description: 'Define a new aggregate function',
    query: 'CREATE AGGREGATE my_agg_func (sfunc = sum, stype = numeric);',
  },
  {
    name: 'CREATE CAST',
    description: 'Define a new cast',
    query:
      'CREATE CAST (my_type AS my_other_type) WITH FUNCTION my_cast_function;',
  },
  {
    name: 'CREATE COLLATION',
    description: 'Define a new collation',
    query: "CREATE COLLATION my_collation (LOCALE = 'en_US.utf8');",
  },
  {
    name: 'CREATE CONVERSION',
    description: 'Define a new encoding conversion',
    query:
      "CREATE CONVERSION utf8_to_latin1 FOR 'UTF8' TO 'LATIN1' FROM function_example;",
  },
  {
    name: 'CREATE DATABASE',
    description: 'Create a new database',
    query: 'CREATE DATABASE my_new_db;',
  },
  {
    name: 'CREATE DOMAIN',
    description: 'Define a new domain',
    query: 'CREATE DOMAIN my_domain AS INTEGER CHECK (VALUE > 0);',
  },
  {
    name: 'CREATE EVENT TRIGGER',
    description: 'Define a new event trigger',
    query:
      'CREATE EVENT TRIGGER my_event_trigger ON ddl_command_start EXECUTE FUNCTION process_event();',
  },
  {
    name: 'CREATE EXTENSION',
    description: 'Install an extension',
    query: 'CREATE EXTENSION "uuid-ossp";',
  },
  {
    name: 'CREATE FOREIGN DATA WRAPPER',
    description: 'Define a new foreign-data wrapper',
    query: 'CREATE FOREIGN DATA WRAPPER my_fdw HANDLER my_fdw_handler;',
  },
  {
    name: 'CREATE FOREIGN TABLE',
    description: 'Define a new foreign table',
    query:
      'CREATE FOREIGN TABLE my_foreign_table (id INT, name VARCHAR) SERVER my_server;',
  },
  {
    name: 'CREATE FUNCTION',
    description: 'Define a new function',
    query:
      'CREATE FUNCTION my_function(param INT) RETURNS INT LANGUAGE SQL AS $$ SELECT param + 1 $$;',
  },
  {
    name: 'CREATE GROUP',
    description: 'Define a new database role (group)',
    query: 'CREATE GROUP my_group;',
  },
  {
    name: 'CREATE INDEX',
    description: 'Define a new index',
    query: 'CREATE INDEX my_index ON my_table (col1);',
  },
  {
    name: 'CREATE LANGUAGE',
    description: 'Define a new procedural language',
    query:
      'CREATE LANGUAGE plpythonu HANDLER call_handler VALIDATOR valfunction;',
  },
  {
    name: 'CREATE MATERIALIZED VIEW',
    description: 'Define a new materialized view',
    query: 'CREATE MATERIALIZED VIEW my_matview AS SELECT * FROM my_table;',
  },
  {
    name: 'CREATE OPERATOR',
    description: 'Define a new operator',
    query:
      'CREATE OPERATOR public.+ (PROCEDURE = my_operator_function, LEFTARG = integer, RIGHTARG = integer);',
  },
  {
    name: 'CREATE OPERATOR CLASS',
    description: 'Define a new operator class',
    query:
      'CREATE OPERATOR CLASS my_op_class FOR TYPE integer USING btree AS OPERATOR 1 <;',
  },
  {
    name: 'CREATE OPERATOR FAMILY',
    description: 'Define a new operator family',
    query: 'CREATE OPERATOR FAMILY my_op_family USING btree;',
  },
  {
    name: 'CREATE POLICY',
    description: 'Define a new row-level security policy for a table',
    query:
      'CREATE POLICY my_policy ON my_table FOR SELECT TO my_role USING (col1 > 0);',
  },
  {
    name: 'CREATE PROCEDURE',
    description: 'Define a new procedure',
    query:
      'CREATE PROCEDURE my_procedure(param INT) LANGUAGE SQL AS $$ SELECT param * 2 $$;',
  },
  {
    name: 'CREATE PUBLICATION',
    description: 'Define a new publication',
    query: 'CREATE PUBLICATION my_pub FOR TABLE my_table;',
  },
  {
    name: 'CREATE ROLE',
    description: 'Define a new database role',
    query: 'CREATE ROLE my_new_role;',
  },
  {
    name: 'CREATE RULE',
    description: 'Define a new rewrite rule',
    query:
      'CREATE RULE my_rule AS ON INSERT TO my_table DO INSTEAD INSERT INTO log_table VALUES (NEW.id, current_timestamp);',
  },
  {
    name: 'CREATE SCHEMA',
    description: 'Define a new schema',
    query: 'CREATE SCHEMA my_schema;',
  },
  {
    name: 'CREATE SEQUENCE',
    description: 'Define a new sequence generator',
    query: 'CREATE SEQUENCE my_seq START 100 INCREMENT BY 1;',
  },
  {
    name: 'CREATE SERVER',
    description: 'Define a new foreign server',
    query:
      "CREATE SERVER my_server FOREIGN DATA WRAPPER my_fdw OPTIONS (host 'localhost', dbname 'mydb');",
  },
  {
    name: 'CREATE STATISTICS',
    description: 'Define extended statistics',
    query:
      'CREATE STATISTICS my_stats (ndistinct) ON col1, col2 FROM my_table;',
  },
  {
    name: 'CREATE SUBSCRIPTION',
    description: 'Define a new subscription',
    query:
      "CREATE SUBSCRIPTION my_sub CONNECTION 'dbname=mydb' PUBLICATION my_pub;",
  },
  {
    name: 'CREATE TABLE',
    description: 'Define a new table',
    query: `CREATE TABLE my_table (
  id SERIAL PRIMARY KEY,
  name VARCHAR(50) NOT NULL
);`,
  },
  {
    name: 'CREATE TABLE AS',
    description: 'Define a new table from the results of a query',
    query: 'CREATE TABLE new_table AS SELECT * FROM my_table WHERE condition;',
  },
  {
    name: 'CREATE TABLESPACE',
    description: 'Define a new tablespace',
    query: "CREATE TABLESPACE my_tablespace LOCATION '/path/to/data';",
  },
  {
    name: 'CREATE TEXT SEARCH CONFIGURATION',
    description: 'Define a new text search configuration',
    query: 'CREATE TEXT SEARCH CONFIGURATION my_text_config (COPY = simple);',
  },
  {
    name: 'CREATE TEXT SEARCH DICTIONARY',
    description: 'Define a new text search dictionary',
    query:
      "CREATE TEXT SEARCH DICTIONARY my_dict (TEMPLATE = snowball, LANGUAGE = 'en');",
  },
  {
    name: 'CREATE TEXT SEARCH PARSER',
    description: 'Define a new text search parser',
    query: 'CREATE TEXT SEARCH PARSER my_parser (FUNCNAME = my_parser_func);',
  },
  {
    name: 'CREATE TEXT SEARCH TEMPLATE',
    description: 'Define a new text search template',
    query: 'CREATE TEXT SEARCH TEMPLATE my_template (INIT = dsimple);',
  },
  {
    name: 'CREATE TRANSFORM',
    description: 'Define a new transform',
    query: `CREATE TRANSFORM FOR my_type LANGUAGE SQL (
  FROM SQL WITH FUNCTION my_func_from_sql_name,
  TO SQL WITH FUNCTION my_func_to_sql_name
);`,
  },
  {
    name: 'CREATE TRIGGER',
    description: 'Define a new trigger',
    query:
      'CREATE TRIGGER my_trigger BEFORE INSERT ON my_table FOR EACH ROW EXECUTE FUNCTION my_trigger_function();',
  },
  {
    name: 'CREATE TYPE',
    description: 'Define a new data type',
    query: "CREATE TYPE my_type AS ENUM ('value1', 'value2', 'value3');",
  },
  {
    name: 'CREATE USER',
    description: 'Define a new database role (user)',
    query: "CREATE USER my_new_user PASSWORD 'password';",
  },
  {
    name: 'CREATE USER MAPPING',
    description: 'Define a new mapping of a user to a foreign server',
    query:
      "CREATE USER MAPPING FOR my_user SERVER my_server OPTIONS (user 'remote_user', password 'remote_password');",
  },
  {
    name: 'CREATE VIEW',
    description: 'Define a new view',
    query: 'CREATE VIEW my_view AS SELECT * FROM my_table WHERE condition;',
  },
  {
    name: 'DEALLOCATE',
    description: 'Deallocate a prepared statement',
    query: 'DEALLOCATE my_statement;',
  },
  {
    name: 'DECLARE',
    description: 'Define a cursor',
    query: 'DECLARE my_cursor CURSOR FOR SELECT * FROM my_table;',
  },
  {
    name: 'DELETE',
    description: 'Delete rows of a table',
    query: 'DELETE FROM my_table WHERE condition;',
  },
  {
    name: 'DISCARD',
    description: 'Discard session state',
    query: 'DISCARD PLANS;',
  },
  {
    name: 'DO',
    description: 'Execute an anonymous code block',
    query: "DO $$ BEGIN RAISE NOTICE 'Hello, world!'; END $$;",
  },
  {
    name: 'DROP ACCESS METHOD',
    description: 'Remove an access method',
    query: 'DROP ACCESS METHOD IF EXISTS my_method;',
  },
  {
    name: 'DROP AGGREGATE',
    description: 'Remove an aggregate function',
    query: 'DROP AGGREGATE IF EXISTS my_agg_func(integer);',
  },
  {
    name: 'DROP CAST',
    description: 'Remove a cast',
    query: 'DROP CAST IF EXISTS (my_type AS my_other_type);',
  },
  {
    name: 'DROP COLLATION',
    description: 'Remove a collation',
    query: 'DROP COLLATION IF EXISTS my_collation;',
  },
  {
    name: 'DROP CONVERSION',
    description: 'Remove a conversion',
    query: 'DROP CONVERSION IF EXISTS utf8_to_latin1;',
  },
  {
    name: 'DROP DATABASE',
    description: 'Remove a database',
    query: 'DROP DATABASE IF EXISTS my_old_db;',
  },
  {
    name: 'DROP DOMAIN',
    description: 'Remove a domain',
    query: 'DROP DOMAIN IF EXISTS my_domain;',
  },
  {
    name: 'DROP EVENT TRIGGER',
    description: 'Remove an event trigger',
    query: 'DROP EVENT TRIGGER IF EXISTS my_event_trigger;',
  },
  {
    name: 'DROP EXTENSION',
    description: 'Remove an extension',
    query: 'DROP EXTENSION IF EXISTS "uuid-ossp";',
  },
  {
    name: 'DROP FOREIGN DATA WRAPPER',
    description: 'Remove a foreign-data wrapper',
    query: 'DROP FOREIGN DATA WRAPPER IF EXISTS my_fdw;',
  },
  {
    name: 'DROP FOREIGN TABLE',
    description: 'Remove a foreign table',
    query: 'DROP FOREIGN TABLE IF EXISTS my_foreign_table;',
  },
  {
    name: 'DROP FUNCTION',
    description: 'Remove a function',
    query: 'DROP FUNCTION IF EXISTS my_function(integer);',
  },
  {
    name: 'DROP GROUP',
    description: 'Remove a database role (group)',
    query: 'DROP GROUP IF EXISTS my_group;',
  },
  {
    name: 'DROP INDEX',
    description: 'Remove an index',
    query: 'DROP INDEX IF EXISTS my_index;',
  },
  {
    name: 'DROP LANGUAGE',
    description: 'Remove a procedural language',
    query: 'DROP LANGUAGE IF EXISTS plpythonu;',
  },
  {
    name: 'DROP MATERIALIZED VIEW',
    description: 'Remove a materialized view',
    query: 'DROP MATERIALIZED VIEW IF EXISTS my_matview;',
  },
  {
    name: 'DROP OPERATOR',
    description: 'Remove an operator',
    query: 'DROP OPERATOR IF EXISTS + (integer, integer);',
  },
  {
    name: 'DROP OPERATOR CLASS',
    description: 'Remove an operator class',
    query: 'DROP OPERATOR CLASS IF EXISTS my_op_class USING btree;',
  },
  {
    name: 'DROP OPERATOR FAMILY',
    description: 'Remove an operator family',
    query: 'DROP OPERATOR FAMILY IF EXISTS my_op_family USING btree;',
  },
  {
    name: 'DROP OWNED',
    description: 'Remove database objects owned by a database role',
    query: 'DROP OWNED BY my_role;',
  },
  {
    name: 'DROP POLICY',
    description: 'Remove a row-level security policy from a table',
    query: 'DROP POLICY IF EXISTS my_policy ON my_table;',
  },
  {
    name: 'DROP PROCEDURE',
    description: 'Remove a procedure',
    query: 'DROP PROCEDURE IF EXISTS my_procedure(integer);',
  },
  {
    name: 'DROP PUBLICATION',
    description: 'Remove a publication',
    query: 'DROP PUBLICATION IF EXISTS my_pub;',
  },
  {
    name: 'DROP ROLE',
    description: 'Remove a database role',
    query: 'DROP ROLE IF EXISTS my_old_role;',
  },
  {
    name: 'DROP ROUTINE',
    description: 'Remove a routine (function or procedure)',
    query: 'DROP ROUTINE IF EXISTS my_function(integer);',
  },
  {
    name: 'DROP RULE',
    description: 'Remove a rewrite rule',
    query: 'DROP RULE IF EXISTS my_rule ON my_table',
  },
  {
    name: 'DROP SCHEMA',
    description: 'Remove a schema',
    query: 'DROP SCHEMA IF EXISTS my_old_schema;',
  },
  {
    name: 'DROP SEQUENCE',
    description: 'Remove a sequence',
    query: 'DROP SEQUENCE IF EXISTS my_seq;',
  },
  {
    name: 'DROP SERVER',
    description: 'Remove a foreign server descriptor',
    query: 'DROP SERVER IF EXISTS my_server;',
  },
  {
    name: 'DROP STATISTICS',
    description: 'Remove extended statistics',
    query: 'DROP STATISTICS IF EXISTS my_stats;',
  },
  {
    name: 'DROP SUBSCRIPTION',
    description: 'Remove a subscription',
    query: 'DROP SUBSCRIPTION IF EXISTS my_sub;',
  },
  {
    name: 'DROP TABLE',
    description: 'Remove a table',
    query: 'DROP TABLE IF EXISTS my_table;',
  },
  {
    name: 'DROP TABLESPACE',
    description: 'Remove a tablespace',
    query: 'DROP TABLESPACE IF EXISTS my_tablespace;',
  },
  {
    name: 'DROP TEXT SEARCH CONFIGURATION',
    description: 'Remove a text search configuration',
    query: 'DROP TEXT SEARCH CONFIGURATION IF EXISTS my_text_config;',
  },
  {
    name: 'DROP TEXT SEARCH DICTIONARY',
    description: 'Remove a text search dictionary',
    query: 'DROP TEXT SEARCH DICTIONARY IF EXISTS my_dict;',
  },
  {
    name: 'DROP TEXT SEARCH PARSER',
    description: 'Remove a text search parser',
    query: 'DROP TEXT SEARCH PARSER IF EXISTS my_parser;',
  },
  {
    name: 'DROP TEXT SEARCH TEMPLATE',
    description: 'Remove a text search template',
    query: 'DROP TEXT SEARCH TEMPLATE IF EXISTS my_template;',
  },
  {
    name: 'DROP TRANSFORM',
    description: 'Remove a transform',
    query: 'DROP TRANSFORM IF EXISTS FOR my_type LANGUAGE lang_name;',
  },
  {
    name: 'DROP TRIGGER',
    description: 'Remove a trigger',
    query: 'DROP TRIGGER IF EXISTS my_trigger ON my_table;',
  },
  {
    name: 'DROP TYPE',
    description: 'Remove a data type',
    query: 'DROP TYPE IF EXISTS my_type;',
  },
  {
    name: 'DROP USER',
    description: 'Remove a database role (user)',
    query: 'DROP USER IF EXISTS my_old_user;',
  },
  {
    name: 'DROP USER MAPPING',
    description: 'Remove a user mapping for a foreign server',
    query: 'DROP USER MAPPING IF EXISTS FOR my_user SERVER my_server;',
  },
  {
    name: 'DROP VIEW',
    description: 'Remove a view',
    query: 'DROP VIEW IF EXISTS my_view;',
  },
  {
    name: 'END',
    description: 'End a transaction block',
    query: 'END;',
  },
  {
    name: 'EXECUTE',
    description: 'Execute a prepared statement',
    query: 'EXECUTE my_prepared_stmt;',
  },
  {
    name: 'EXPLAIN',
    description: 'Show the execution plan of a statement',
    query: 'EXPLAIN SELECT * FROM my_table WHERE condition;',
  },
  {
    name: 'FETCH',
    description: 'Retrieve rows from a query using a cursor',
    query: 'FETCH NEXT FROM my_cursor;',
  },
  {
    name: 'GRANT',
    description: 'Define access privileges',
    query: 'GRANT SELECT ON my_table TO my_role;',
  },
  {
    name: 'IMPORT FOREIGN SCHEMA',
    description: 'Import table definitions from a foreign server',
    query:
      'IMPORT FOREIGN SCHEMA public FROM SERVER my_server INTO my_local_schema;',
  },
  {
    name: 'INSERT',
    description: 'Create new rows in a table',
    query: 'INSERT INTO my_table (col1, col2) VALUES (val1, val2);',
  },
  {
    name: 'LISTEN',
    description: 'Listen for a notification',
    query: 'LISTEN my_channel;',
  },
  {
    name: 'LOAD',
    description: 'Load a shared library file',
    query: "LOAD '/plugins/special.so';",
  },
  {
    name: 'LOCK',
    description: 'Explicitly acquire locks on rows or tables',
    query: 'LOCK TABLE my_table IN SHARE MODE;',
  },
  {
    name: 'MERGE',
    description: 'Conditionally insert, update, or delete rows of a table',
    query: `MERGE INTO target_table USING source_table ON target_table.id = source_table.id
WHEN MATCHED THEN UPDATE SET target_table.col1 = source_table.col1
WHEN NOT MATCHED THEN INSERT (id, col1) VALUES (source_table.id, source_table.col1);`,
  },
  {
    name: 'MOVE',
    description: 'Move a cursor to a new position',
    query: 'MOVE NEXT FROM my_cursor;',
  },
  {
    name: 'NOTIFY',
    description: 'Send a notification',
    query: "NOTIFY my_channel, 'Payload message';",
  },
  {
    name: 'PREPARE',
    description: 'Prepare a statement for execution',
    query: 'PREPARE my_statement AS SELECT * FROM my_table WHERE condition;',
  },
  {
    name: 'PREPARE TRANSACTION',
    description: 'Prepare the current transaction for two-phase commit',
    query: "PREPARE TRANSACTION 'my_prepared_txn';",
  },
  {
    name: 'REASSIGN OWNED',
    description: 'Reassign database objects owned by a role to another role',
    query: 'REASSIGN OWNED BY my_old_role TO my_new_role;',
  },
  {
    name: 'REFRESH MATERIALIZED VIEW',
    description: 'Replace the data of a materialized view',
    query: 'REFRESH MATERIALIZED VIEW my_matview;',
  },
  {
    name: 'REINDEX',
    description: 'Rebuild indexes',
    query: 'REINDEX INDEX my_index;',
  },
  {
    name: 'RELEASE',
    description: 'Release a previously defined savepoint',
    query: 'RELEASE SAVEPOINT my_savepoint;',
  },
  {
    name: 'RESET',
    description:
      'Restore the value of a run-time parameter to the default value',
    query: 'RESET my_parameter;',
  },
  {
    name: 'REVOKE',
    description: 'Remove access privileges',
    query: 'REVOKE SELECT ON my_table FROM my_role;',
  },
  {
    name: 'ROLLBACK',
    description: 'Roll back the current transaction',
    query: 'ROLLBACK;',
  },
  {
    name: 'ROLLBACK PREPARED',
    description:
      'Roll back a transaction that was earlier prepared for two-phase commit',
    query: "ROLLBACK PREPARED 'my_prepared_txn';",
  },
  {
    name: 'ROLLBACK TO SAVEPOINT',
    description: 'Roll back to a savepoint',
    query: 'ROLLBACK TO SAVEPOINT my_savepoint;',
  },
  {
    name: 'SAVEPOINT',
    description: 'Define a new savepoint within the current transaction',
    query: 'SAVEPOINT my_savepoint;',
  },
  {
    name: 'SECURITY LABEL',
    description: 'Define or change a security label applied to an object',
    query: "SECURITY LABEL ON TABLE my_table IS 'security_label';",
  },
  {
    name: 'SELECT',
    description:
      'Retrieve rows from a table or view or a result set of a query',
    query: 'SELECT * FROM my_table;',
  },
  {
    name: 'SELECT INTO',
    description:
      'Store the result of a query (single row) into variables or a record',
    query: 'SELECT col1, col2 INTO tmp_table FROM my_table WHERE condition;',
  },
  {
    name: 'SET',
    description: 'Change a run-time parameter',
    query: 'SET search_path TO my_schema;',
  },
  {
    name: 'SET CONSTRAINTS',
    description: 'Set constraint check timing for the current transaction',
    query: 'SET CONSTRAINTS my_constraint DEFERRED;',
  },
  {
    name: 'SET ROLE',
    description: 'Set the current role for the current session',
    query: 'SET ROLE my_role;',
  },
  {
    name: 'SET SESSION AUTHORIZATION',
    description:
      'Set the session user identifier and the current user identifier of the current session',
    query: 'SET SESSION AUTHORIZATION my_user;',
  },
  {
    name: 'SET TRANSACTION',
    description: 'Set the characteristics of the current transaction',
    query: 'SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;',
  },
  {
    name: 'SHOW',
    description: 'Show the value of a run-time parameter',
    query: 'SHOW search_path;',
  },
  {
    name: 'START TRANSACTION',
    description: 'Start a transaction block',
    query: 'START TRANSACTION;',
  },
  {
    name: 'TRUNCATE',
    description: 'Empty a table or set of tables',
    query: 'TRUNCATE TABLE my_table;',
  },
  {
    name: 'UNLISTEN',
    description: 'Stop listening for a notification',
    query: 'UNLISTEN my_channel;',
  },
  {
    name: 'UPDATE',
    description: 'Update rows of a table',
    query: 'UPDATE my_table SET col1 = val1 WHERE condition;',
  },
  {
    name: 'VACUUM',
    description: 'Reclaim storage occupied by dead tuples',
    query: 'VACUUM my_table;',
  },
  {
    name: 'VACUUM FULL',
    description: 'Reclaim storage and optionally reorders rows',
    query: 'VACUUM FULL my_table;',
  },
  {
    name: 'VACUUM FREEZE',
    description: 'Reclaim storage and mark all tuples as frozen',
    query: 'VACUUM FREEZE my_table;',
  },
  {
    name: 'VACUUM ANALYZE',
    description: 'Reclaim storage and update statistics',
    query: 'VACUUM ANALYZE my_table;',
  },
  {
    name: 'VACUUM VERBOSE',
    description: 'Reclaim storage and display progress information',
    query: 'VACUUM VERBOSE my_table;',
  },
  {
    name: 'VALUES',
    description: 'Compute a set of rows',
    query: "VALUES (1, 'one'), (2, 'two'), (3, 'three');",
  },
];

const missingQueriesForTest = DDLStatements.filter(
  (statement) =>
    !queries.some((query) => query.name === statement && query.query)
);
if (missingQueriesForTest.length > 0) {
  logger.infoEvent('missingQueriesForTest', missingQueriesForTest);
}

const statementTypeCount: Map<string, number> = new Map();
const statementTypeQueries: Map<string, unknown[]> = new Map();

type PostgresStmts =
  | 'AlterCollationStmt'
  | 'AlterDatabaseRefreshCollStmt'
  | 'AlterDatabaseSetStmt'
  | 'AlterDatabaseStmt'
  | 'AlterDefaultPrivilegesStmt'
  | 'AlterDomainStmt'
  | 'AlterEnumStmt'
  | 'AlterEventTrigStmt'
  | 'AlterExtensionContentsStmt'
  | 'AlterExtensionStmt'
  | 'AlterFdwStmt'
  | 'AlterForeignServerStmt'
  | 'AlterFunctionStmt'
  | 'AlterObjectDependsStmt'
  | 'AlterObjectSchemaStmt'
  | 'AlterOperatorStmt'
  | 'AlterOpFamilyStmt'
  | 'AlterOwnerStmt'
  | 'AlterPolicyStmt'
  | 'AlterPublicationStmt'
  | 'AlterRoleSetStmt'
  | 'AlterRoleStmt'
  | 'AlterSeqStmt'
  | 'AlterStatsStmt'
  | 'AlterSubscriptionStmt'
  | 'AlterSystemStmt'
  | 'AlterTableMoveAllStmt'
  | 'AlterTableSpaceOptionsStmt'
  | 'AlterTableStmt'
  | 'AlterTSConfigurationStmt'
  | 'AlterTSDictionaryStmt'
  | 'AlterTypeStmt'
  | 'AlterUserMappingStmt'
  | 'CallStmt'
  | 'CheckPointStmt'
  | 'ClosePortalStmt'
  | 'ClusterStmt'
  | 'CommentStmt'
  | 'CompositeTypeStmt'
  | 'ConstraintsSetStmt'
  | 'CopyStmt'
  | 'CreateAmStmt'
  | 'CreateCastStmt'
  | 'CreateConversionStmt'
  | 'CreatedbStmt'
  | 'CreateDomainStmt'
  | 'CreateEnumStmt'
  | 'CreateEventTrigStmt'
  | 'CreateExtensionStmt'
  | 'CreateFdwStmt'
  | 'CreateForeignServerStmt'
  | 'CreateForeignTableStmt'
  | 'CreateFunctionStmt'
  | 'CreateOpClassStmt'
  | 'CreateOpFamilyStmt'
  | 'CreatePLangStmt'
  | 'CreatePolicyStmt'
  | 'CreatePublicationStmt'
  | 'CreateRangeStmt'
  | 'CreateRoleStmt'
  | 'CreateSchemaStmt'
  | 'CreateSeqStmt'
  | 'CreateStatsStmt'
  | 'CreateStmt'
  | 'CreateSubscriptionStmt'
  | 'CreateTableAsStmt'
  | 'CreateTableSpaceStmt'
  | 'CreateTransformStmt'
  | 'CreateTrigStmt'
  | 'CreateUserMappingStmt'
  | 'DeallocateStmt'
  | 'DeclareCursorStmt'
  | 'DefineStmt'
  | 'DeleteStmt'
  | 'DiscardStmt'
  | 'DoStmt'
  | 'DropSubscriptionStmt'
  | 'DropdbStmt'
  | 'DropOwnedStmt'
  | 'DropRoleStmt'
  | 'DropStmt'
  | 'DropTableSpaceStmt'
  | 'DropUserMappingStmt'
  | 'ExecuteStmt'
  | 'ExplainStmt'
  | 'FetchStmt'
  | 'GrantRoleStmt'
  | 'GrantStmt'
  | 'ImportForeignSchemaStmt'
  | 'IndexStmt'
  | 'InsertStmt'
  | 'ListenStmt'
  | 'LoadStmt'
  | 'LockStmt'
  | 'MergeStmt'
  | 'NotifyStmt'
  | 'PlannedStmt'
  | 'PLAssignStmt'
  | 'PLpgSQL_stmt'
  | 'PrepareStmt'
  | 'RawStmt'
  | 'ReassignOwnedStmt'
  | 'RefreshMatViewStmt'
  | 'ReindexStmt'
  | 'RenameStmt'
  | 'ReplicaIdentityStmt'
  | 'ReturnStmt'
  | 'RuleStmt'
  | 'SecLabelStmt'
  | 'SelectStmt'
  | 'SetOperationStmt'
  | 'TransactionStmt'
  | 'TruncateStmt'
  | 'UnlistenStmt'
  | 'UpdateStmt'
  | 'VacuumStmt'
  | 'VariableSetStmt'
  | 'VariableShowStmt'
  | 'ViewStmt';

export const extractQueryMetadata = (query: string) => {
  try {
    const parsed = parseQuery(query);
    let statementType: PostgresStmts = parsed
      .statementsList[0]! as PostgresStmts;
    if (statementType === 'TransactionStmt') {
      const kind = parsed.result.stmts[0].stmt.TransactionStmt.kind;
      statementType += `/${kind}`;
      if (kind === 'TRANS_STMT_ROLLBACK') {
        const baseQuery = query.split(' ').filter(Boolean).join(' ');
        let subType = 'rollback';
        if (baseQuery.includes('ABORT')) {
          subType = 'abort';
        }
        statementType += `/${subType}`;
      } else if (kind === 'TRANS_STMT_COMMIT') {
        const baseQuery = query.split(' ').filter(Boolean).join(' ');
        let subType = 'commit';
        if (baseQuery.includes('END')) {
          subType = 'end';
        }
        statementType += `/${subType}`;
      }
    } else if (statementType === 'AlterObjectSchemaStmt') {
      const kind = parsed.result.stmts[0].stmt.AlterObjectSchemaStmt.objectType;
      statementType += `/${kind}`;
    } else if (statementType === 'AlterRoleStmt') {
      const baseQuery = query.split(' ').filter(Boolean).join(' ');
      let roleType = 'any';
      if (baseQuery.includes('ALTER GROUP')) {
        roleType = 'group';
      } else if (baseQuery.includes('ALTER ROLE')) {
        roleType = 'role';
      } else if (baseQuery.includes('ALTER USER')) {
        roleType = 'user';
      }
      statementType += `/${roleType}`;
    } else if (statementType === 'RenameStmt') {
      const kind = parsed.result.stmts[0].stmt.RenameStmt.renameType;
      statementType += `/${kind}`;
    } else if (statementType === 'AlterOwnerStmt') {
      const kind = parsed.result.stmts[0].stmt.AlterOwnerStmt.objectType;
      statementType += `/${kind}`;
    } else if (statementType === 'AlterTableStmt') {
      const kind = parsed.result.stmts[0].stmt.AlterTableStmt.objtype;
      const subCommands = [
        ...new Set(
          parsed.result.stmts[0].stmt.AlterTableStmt.cmds.map(
            (cmd: { AlterTableCmd: { subtype: string } }) =>
              cmd.AlterTableCmd.subtype
          )
        ),
      ]
        .sort()
        .join(',');
      statementType += `/${kind}/(${subCommands})`;
    } else if (statementType === 'VacuumStmt') {
      const vacuum = parsed.result.stmts[0].stmt.VacuumStmt.is_vacuumcmd
        ? 'VACUUM'
        : 'OTHER';
      const options = [
        ...new Set(
          parsed.result.stmts[0].stmt.VacuumStmt.options?.map(
            (option: { DefElem: { defname: string } }) => option.DefElem.defname
          )
        ),
      ]
        .sort()
        .join(',');
      statementType += `/${vacuum}/(${options})`;
    } else if (statementType === 'DefineStmt') {
      const kind = parsed.result.stmts[0].stmt.DefineStmt.kind;
      statementType += `/${kind}`;
    } else if (statementType === 'CreateRoleStmt') {
      const kind = parsed.result.stmts[0].stmt.CreateRoleStmt.stmt_type;
      statementType += `/${kind}`;
    } else if (statementType === 'DropStmt') {
      const kind = parsed.result.stmts[0].stmt.DropStmt.removeType;
      statementType += `/${kind}`;
    } else if (statementType === 'DropRoleStmt') {
      const baseQuery = query.split(' ').filter(Boolean).join(' ');
      let roleType = 'any';
      if (baseQuery.includes('DROP GROUP')) {
        roleType = 'group';
      } else if (baseQuery.includes('DROP ROLE')) {
        roleType = 'role';
      } else if (baseQuery.includes('DROP USER')) {
        roleType = 'user';
      }
      statementType += `/${roleType}`;
    } else if (statementType === 'VariableSetStmt') {
      const kind = parsed.result.stmts[0].stmt.VariableSetStmt.kind;
      const name = parsed.result.stmts[0].stmt.VariableSetStmt.name;
      statementType += `/${kind}/(${name})`;
    } else if (statementType === 'SelectStmt') {
      const selectStmt = parsed.result.stmts[0].stmt.SelectStmt;
      if (selectStmt.intoClause) {
        statementType += '/into';
      } else if (selectStmt.valuesLists) {
        statementType += '/values';
      }
    } else if (statementType === 'CreateFunctionStmt') {
      const type = parsed.result.stmts[0].stmt.CreateFunctionStmt.is_procedure
        ? 'procedure'
        : 'function';
      statementType += `/${type}`;
    } else if (statementType === 'CreateTableAsStmt') {
      const type = parsed.result.stmts[0].stmt.CreateTableAsStmt.objtype;
      statementType += `/${type}`;
    } else if (statementType === 'FetchStmt') {
      const type = parsed.result.stmts[0].stmt.FetchStmt.ismove
        ? 'move'
        : 'fetch';
      statementType += `/${type}`;
    } else if (statementType === 'GrantStmt') {
      const type = parsed.result.stmts[0].stmt.GrantStmt.is_grant
        ? 'grant'
        : 'revoke';
      statementType += `/${type}`;
    }
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

export const validateQueries = () => {
  for (const query of queries) {
    if (query.query) {
      try {
        const parsed = parseQuery(query.query);
        let statementType = parsed.statementsList[0]!;
        if (statementType === 'TransactionStmt') {
          const kind = parsed.result.stmts[0].stmt.TransactionStmt.kind;
          statementType += `/${kind}`;
          if (kind === 'TRANS_STMT_ROLLBACK') {
            const baseQuery = query.query.split(' ').filter(Boolean).join(' ');
            let subType = 'rollback';
            if (baseQuery.includes('ABORT')) {
              subType = 'abort';
            }
            statementType += `/${subType}`;
          } else if (kind === 'TRANS_STMT_COMMIT') {
            const baseQuery = query.query.split(' ').filter(Boolean).join(' ');
            let subType = 'commit';
            if (baseQuery.includes('END')) {
              subType = 'end';
            }
            statementType += `/${subType}`;
          }
        } else if (statementType === 'AlterObjectSchemaStmt') {
          const kind =
            parsed.result.stmts[0].stmt.AlterObjectSchemaStmt.objectType;
          statementType += `/${kind}`;
        } else if (statementType === 'AlterRoleStmt') {
          const baseQuery = query.query.split(' ').filter(Boolean).join(' ');
          let roleType = 'any';
          if (baseQuery.includes('ALTER GROUP')) {
            roleType = 'group';
          } else if (baseQuery.includes('ALTER ROLE')) {
            roleType = 'role';
          } else if (baseQuery.includes('ALTER USER')) {
            roleType = 'user';
          }
          statementType += `/${roleType}`;
        } else if (statementType === 'RenameStmt') {
          const kind = parsed.result.stmts[0].stmt.RenameStmt.renameType;
          statementType += `/${kind}`;
        } else if (statementType === 'AlterOwnerStmt') {
          const kind = parsed.result.stmts[0].stmt.AlterOwnerStmt.objectType;
          statementType += `/${kind}`;
        } else if (statementType === 'AlterTableStmt') {
          const kind = parsed.result.stmts[0].stmt.AlterTableStmt.objtype;
          const subCommands = [
            ...new Set(
              parsed.result.stmts[0].stmt.AlterTableStmt.cmds.map(
                (cmd: { AlterTableCmd: { subtype: string } }) =>
                  cmd.AlterTableCmd.subtype
              )
            ),
          ]
            .sort()
            .join(',');
          statementType += `/${kind}/(${subCommands})`;
        } else if (statementType === 'VacuumStmt') {
          const vacuum = parsed.result.stmts[0].stmt.VacuumStmt.is_vacuumcmd
            ? 'VACUUM'
            : 'OTHER';
          const options = [
            ...new Set(
              parsed.result.stmts[0].stmt.VacuumStmt.options?.map(
                (option: { DefElem: { defname: string } }) =>
                  option.DefElem.defname
              )
            ),
          ]
            .sort()
            .join(',');
          statementType += `/${vacuum}/(${options})`;
        } else if (statementType === 'DefineStmt') {
          const kind = parsed.result.stmts[0].stmt.DefineStmt.kind;
          statementType += `/${kind}`;
        } else if (statementType === 'CreateRoleStmt') {
          const kind = parsed.result.stmts[0].stmt.CreateRoleStmt.stmt_type;
          statementType += `/${kind}`;
        } else if (statementType === 'DropStmt') {
          const kind = parsed.result.stmts[0].stmt.DropStmt.removeType;
          statementType += `/${kind}`;
        } else if (statementType === 'DropRoleStmt') {
          const baseQuery = query.query.split(' ').filter(Boolean).join(' ');
          let roleType = 'any';
          if (baseQuery.includes('DROP GROUP')) {
            roleType = 'group';
          } else if (baseQuery.includes('DROP ROLE')) {
            roleType = 'role';
          } else if (baseQuery.includes('DROP USER')) {
            roleType = 'user';
          }
          statementType += `/${roleType}`;
        } else if (statementType === 'VariableSetStmt') {
          const kind = parsed.result.stmts[0].stmt.VariableSetStmt.kind;
          const name = parsed.result.stmts[0].stmt.VariableSetStmt.name;
          statementType += `/${kind}/(${name})`;
        } else if (statementType === 'SelectStmt') {
          const selectStmt = parsed.result.stmts[0].stmt.SelectStmt;
          if (selectStmt.intoClause) {
            statementType += '/into';
          } else if (selectStmt.valuesLists) {
            statementType += '/values';
          }
        } else if (statementType === 'CreateFunctionStmt') {
          const type = parsed.result.stmts[0].stmt.CreateFunctionStmt
            .is_procedure
            ? 'procedure'
            : 'function';
          statementType += `/${type}`;
        } else if (statementType === 'CreateTableAsStmt') {
          const type = parsed.result.stmts[0].stmt.CreateTableAsStmt.objtype;
          statementType += `/${type}`;
        } else if (statementType === 'FetchStmt') {
          const type = parsed.result.stmts[0].stmt.FetchStmt.ismove
            ? 'move'
            : 'fetch';
          statementType += `/${type}`;
        } else if (statementType === 'GrantStmt') {
          const type = parsed.result.stmts[0].stmt.GrantStmt.is_grant
            ? 'grant'
            : 'revoke';
          statementType += `/${type}`;
        }

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
