import logging
import json
import os
import inspect
from datetime import datetime, timezone
from uuid import uuid4
from typing import Union
import contextvars
import httpx
import traceback

request_id_context = contextvars.ContextVar("request_id", default=None)
user_context = contextvars.ContextVar("user_data", default=None)

def set_user_data(key: str, value: str):
  user_data = user_context.get().copy()
  user_data[key] = value
  user_context.set(user_data)

def get_user_data() -> dict:
  return user_context.get()

class UvicornJSONLogFormatter(logging.Formatter):
  def format(self, record: logging.LogRecord) -> str:
    level = record.levelname.lower()
    # timestamp = datetime.now(timezone.utc).strftime("%d/%b/%Y %H:%M:%S.%f")[:-3] + "UTC"
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3]
    environment = os.getenv("ENVIRONMENT", "local")
    log_record = {
      "severity": level,
      "app@timestamp": timestamp,
      "environment": environment,
      "file": f"{record.pathname}:{record.lineno}",
      "message": record.getMessage(),
    }

    if hasattr(record, "req_id"):
      log_record["req-id"] = record.req_id
    if hasattr(record, "event"):
      log_record["event"] = record.event

    return json.dumps(log_record, separators=(",", ":"))

class CustomLogger:
  def __init__(self, event: str):
    self.event = event
    self.environment = os.getenv("NODE_ENV", "dev")
    self.logger = logging.getLogger("custom_logger")
    if not self.logger.hasHandlers():
      handler = logging.StreamHandler()
      formatter = logging.Formatter('%(message)s')
      handler.setFormatter(formatter)
      self.logger.addHandler(handler)
    self.logger.setLevel(logging.INFO)

  def _get_caller_info(self):
    """ Get the current file, line number, and column number of the function that called the logger. """
    frame = None
    for frame_record in inspect.stack()[2:]:
      frame = frame_record.frame
      if "logger.py" not in frame.f_code.co_filename:
        break
    filename = frame.f_code.co_filename
    lineno = frame.f_lineno
    colno = frame.f_lasti
    return f"{filename}:{lineno}:{colno}"

  def _get_req_id(self):
    """ Get the request ID from the context. """
    return request_id_context.get() or str(uuid4())

  def _format_message(self, message: Union[str, dict, int, float, bool]) -> str:
    """ Format the message to ensure it is a string in format as JSON 'stringified' dictionaries. """
    if isinstance(message, dict):
      try:
        return json.dumps(message, separators=(",", ":"))
      except Exception:
        return str(message)
    return str(message)

  def _log(self, severity: str, message: Union[str, dict, int, float, bool]):
    """ General logging method used by all other logging methods. """
    user_data = get_user_data()
    if user_data:
      log_data = {
        "severity": severity,
        "app@timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3],
        "environment": self.environment,
        "file": self._get_caller_info(),
        "message": self._format_message(message),
        "req-id": self._get_req_id(),
        "session-id": user_data.get("session_id"),
        "user": user_data.get("user"),
        "event": self.event,
      }
    else:
      log_data = {
        "severity": severity,
        "app@timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3],
        "environment": self.environment,
        "file": self._get_caller_info(),
        "message": self._format_message(message),
        "req-id": self._get_req_id(),
        "event": self.event,
      }
    self.logger.info(json.dumps(log_data, separators=(",", ":")))

  def _log_db(self, severity: str, sql: str, sql_bindings, query_uid, message: Union[str, dict, int, float, bool]):
    """ General logging method for database queries and events, used by all other database logging methods. """
    user_data = get_user_data()
    if user_data:
      log_data = {
        "severity": severity,
        "app@timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3],
        "environment": self.environment,
        "file": self._get_caller_info(),
        "message": self._format_message(message),
        "sql": sql,
        "sqlBindings": sql_bindings,
        "queryUid": query_uid,
        "req-id": self._get_req_id(),
        "session-id": user_data.get("session_id"),
        "user": user_data.get("user"),
        "event": self.event,
      }
    else:
      log_data = {
        "severity": severity,
        "app@timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3],
        "environment": self.environment,
        "file": self._get_caller_info(),
        "message": self._format_message(message),
        "sql": sql,
        "sqlBindings": sql_bindings,
        "queryUid": query_uid,
        "req-id": self._get_req_id(),
        "event": self.event,
      }
    self.logger.info(json.dumps(log_data, separators=(",", ":")))

  def info(self, message: Union[str, dict, int, float, bool]):
    """ Log with info severity."""
    self._log("info", message)

  def info_db(self, sql: str, sql_bindings, query_uid, message: Union[str, dict, int, float, bool]):
    """ Log with info severity for database queries and events."""
    self._log_db("info", sql, sql_bindings, query_uid, message)

  def warn(self, message: Union[str, dict, int, float, bool]):
    """ Log with warning severity."""
    self._log("warn", message)

  def warn_db(self, sql: str, sql_bindings, query_uid, message: Union[str, dict, int, float, bool]):
    """ Log with warning severity for database queries and events."""
    self._log_db("warn", sql, sql_bindings, query_uid, message)

  def error(self, message: Union[str, dict, int, float, bool]):
    """ Log with error severity."""
    self._log("error", message)

  def error_db(self, sql: str, sql_bindings, query_uid, message: Union[str, dict, int, float, bool]):
    """ Log with error severity for database queries and events."""
    self._log_db("error", sql, sql_bindings, query_uid, message)

  def log_exception(self, exc: Exception, additional_info: dict = None):
    """ Log an exception with additional information. """
    error_data = {
      "error_type": type(exc).__name__,
      "error_message": str(exc),
      "traceback": traceback.format_exc(),
    }

    if additional_info:
      error_data.update(additional_info)

    self.error(error_data)

  def log_httpx_exception(self, exc: httpx.RequestError):
    """ Log a httpx.RequestError with custom details. """
    self.log_exception(exc, {
      "request_url": str(exc.request.url) if exc.request else 'N/A',
    })
