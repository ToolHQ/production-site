import os
import time
import uuid

from psycopg2 import ProgrammingError
from sqlalchemy import create_engine, text, Engine, event
from sqlalchemy.engine import CursorResult
from sqlalchemy.exc import SQLAlchemyError, OperationalError
import cx_Oracle

from app.libs.logger import CustomLogger

db_query_logger = CustomLogger("DB QUERY")
db_query_connection_error_logger = CustomLogger("DB QUERY CONNECTION ERROR")

NODE_ENV = os.getenv("NODE_ENV", "dev")

def log_query_execution(query, queryBindings, query_uid, sql_method, autocommit, elapsed_time):
  db_query_logger.info_db(
    query,
    queryBindings,
    query_uid,
    {
      "method": sql_method,
      "autoCommit": autocommit,
      "responseTime": f"{elapsed_time}ms",
    },
  )

def get_sql_method(query):
  sql_method = query.strip().split()[0].upper()
  return sql_method

def is_autocommit(connection):
  driver_connection = connection.connection.driver_connection
  isolation_level = driver_connection.get_transaction_status()
  return isolation_level == 0

singleton_engines = {}

class DBConnection:
  def __init__(self, engine: Engine, schema=None):
    self.engine = engine
    self.schema = schema

  def execute_raw_query_with_logging_simple_committed(self, query, params=None, omitParamsFromLog=False):
    start_time = time.time()

    try:
      with self.engine.connect().execution_options(isolation_level="AUTOCOMMIT") as connection:
        autocommit = False
        if self.schema and self.schema != "ORACLE_SCHEMA":
          connection.execute(text(f"SET search_path TO {self.schema}"))
          autocommit = is_autocommit(connection)
        raw_sql_query = text(query)
        query_uid = str(uuid.uuid4())
        sql_method = get_sql_method(str(raw_sql_query))
        compiled_query = raw_sql_query.compile(compile_kwargs={"literal_binds": True})
        result: CursorResult = connection.execute(raw_sql_query, params, execution_options={"autocommit": True})
        final_result = None
        if result.returns_rows:
          final_result = list(result)
        elapsed_time = round((time.time() - start_time) * 1000)
        if omitParamsFromLog:
          log_query_execution(str(compiled_query), [], query_uid, sql_method, autocommit, elapsed_time)
        else:
          log_query_execution(str(compiled_query), params or [], query_uid, sql_method, autocommit, elapsed_time)
        return final_result
    except ProgrammingError as e:
      db_query_connection_error_logger.error(f"Failed to connect using DSN: {e} -> {self.engine.url}")
      raise
    except OperationalError as e:
      db_query_connection_error_logger.error(f"Database connection failed: {e} -> {self.engine.url}")
      raise
    except SQLAlchemyError as e:
      db_query_connection_error_logger.error(f"Query execution failed: {e} -> {self.engine.url}")
      raise

  def execute_raw_query_with_logging(self, query, params=None):
    start_time = time.time()

    try:
      with self.engine.connect() as connection:
        autocommit = False
        if self.schema and self.schema != "ORACLE_SCHEMA":
          connection.execute(text(f"SET search_path TO {self.schema}"))
          autocommit = is_autocommit(connection)
        raw_sql_query = text(query)
        query_uid = str(uuid.uuid4())
        sql_method = get_sql_method(str(raw_sql_query))
        compiled_query = raw_sql_query.compile(compile_kwargs={"literal_binds": True})
        result: CursorResult = connection.execute(raw_sql_query, params)
        elapsed_time = round((time.time() - start_time) * 1000, 3)
        log_query_execution(str(compiled_query), params or [], query_uid, sql_method, autocommit, elapsed_time)
        if result.returns_rows:
          for row in result:
            yield row
    except ProgrammingError as e:
      db_query_connection_error_logger.error(f"Failed to connect using DSN: {e} -> {self.engine.url}")
      raise
    except OperationalError as e:
      db_query_connection_error_logger.error(f"Database connection failed: {e} -> {self.engine.url}")
      raise
    except SQLAlchemyError as e:
      db_query_connection_error_logger.error(f"Query execution failed: {e} -> {self.engine.url}")
      raise
    except Exception as e:
      db_query_connection_error_logger.error(f"Unexpected error executing query: {e} -> {self.engine.url}")
      raise

def get_connection (
  host_env: str,
  port_env: str,
  database_env: str,
  creds_env: str,
  search_path_env: str,
) -> DBConnection:
  if not host_env:
    raise ValueError("get_connection: host_env is not defined")
  if not database_env:
    raise ValueError("get_connection: database_env is not defined")
  if not creds_env:
    raise ValueError("get_connection: creds_env is not defined")
  host_value = os.getenv(host_env)
  database_value = os.getenv(database_env)
  user_value = os.getenv(f"{creds_env}_USER")
  password_value = os.getenv(f"{creds_env}_PASS")
  schema = os.getenv(search_path_env, "public")
  application_name = os.getenv("MY_POD_NAME")

  if host_env == 'ORACLE_CONN_STR':
    dsn = cx_Oracle.makedsn(host_value, 1521, service_name=database_value)
    database_url = f"oracle+cx_oracle://{user_value}:{password_value}@{dsn}"
  else:
    port_value = int(os.getenv(port_env, '5432'))
    # todo: Support sslmode=require
    database_url = f"postgresql://{user_value}:{password_value}@{host_value}:{port_value}/{database_value}?application_name={application_name}"

  ## Singleton pattern to avoid creating multiple connections to the same database
  if singleton_engines.get(database_url):
    return singleton_engines.get(database_url)

  engine = create_engine(database_url)
  if host_env == 'ORACLE_CONN_STR':
    def set_session_defaults(connection, _):
      with connection.cursor() as cursor:
        cursor.execute(f"ALTER SESSION SET CURRENT_SCHEMA = {schema}")
        cursor.execute("BEGIN DBMS_SESSION.SET_IDENTIFIER(:app_name); END;", {"app_name": application_name})
    event.listen(engine, "connect", set_session_defaults)

  conn = DBConnection(engine, schema)
  singleton_engines[database_url] = conn
  return conn
