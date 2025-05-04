import asyncio
from builtins import ExceptionGroup
import uuid
from time import time
import traceback

from fastapi import FastAPI, Request
from fastapi.exceptions import HTTPException
from starlette.responses import JSONResponse

from app.libs.logger import CustomLogger, request_id_context, set_user_data

app = FastAPI(docs_url=None)

# Set up custom loggers
request_received_logger = CustomLogger("Request Received") # Middleware logs
exception_logger = CustomLogger("Exception Ocurred") # Exception logs
task_group_exception_logger = CustomLogger("TaskGroup Exception Handling") # Task group exception logs

parquet_config_key = 'config/tables/items.parquet'

def log_http_exception(exc: HTTPException, request: Request):
  """ Logs HTTPException with custom details. """
  exception_logger.error({
    "method": request.method,
    "url": str(request.url),
    "status_code": exc.status_code,
    "detail": exc.detail,
  })

def log_generic_exception(exc: Exception, request: Request):
  """ Logs any other exceptions with custom details. """
  exception_logger.error({
    "method": request.method,
    "url": str(request.url),
    "status_code": 500,
    "error_type": type(exc).__name__,
    "error_message": str(exc),
    "traceback": traceback.format_exc(),
  })

def log_request_received(request: Request):
  """ Logs request received with custom details. """
  request_received_logger.info({
    "method": request.method,
    "rawPath": request.url.path,
    "url": str(request.url),
    "userAgent": request.headers.get("user-agent", "unknown"),
    "qs": dict(request.query_params),
    "xSystemFrom": request.headers.get("x-system-from", "unknown"),
  })

def log_single_exception(exc: Exception):
  """ Logs a single exception with custom details. """
  task_group_exception_logger.error({
    "error_type": type(exc).__name__,
    "error_message": str(exc),
  })

def log_exception_group(exception_group: ExceptionGroup):
  """ Log all sub-exceptions within an ExceptionGroup using CustomLogger. """
  task_group_exception_logger.error({
    "error_message": f"ExceptionGroup occurred with {len(exception_group.exceptions)} exceptions",
    "error_details": [str(exc) for exc in exception_group.exceptions],
  })
  for sub_exception in exception_group.exceptions:
    log_single_exception(sub_exception)

class RequestLogger:
  def __init__(self, start_time, method, url, query_params, headers, ip_address):
    self.start_time = start_time
    self.method = method
    self.url = url
    self.query_params = query_params
    self.headers = headers
    self.ip_address = ip_address
    self.body_length = 0

  def update_body_length(self, chunk_size):
    self.body_length += chunk_size

  def calculate_response_time(self):
    process_time = time() - self.start_time
    self.response_time_ms = f"{process_time * 1000:.3f}ms"

  def log(self, status_code):
    severity = "info" if 200 <= status_code < 300 else "error"
    request_received_logger.__getattribute__(severity)({
      "method": self.method,
      "rawPath": self.url.path,
      "url": str(self.url),
      "statusCode": status_code,
      "responseTime": self.response_time_ms,
      "bodyLength": self.body_length,
      "userAgent": self.headers.get("user-agent", "unknown"),
      "ipAddress": self.ip_address,
      "qs": dict(self.query_params),
      "xSystemFrom": self.headers.get("x-system-from", "unknown"),
    })

# Middleware to log requests and handle exceptions, logging except requests to GET /health
async def request_logger_middleware(request: Request, call_next: callable):
  req_id = str(uuid.uuid4())
  request_id_context.set(req_id)
  start_time = time()

  try:
    if request.url.path == "/health":
      return await call_next(request)

    # Extract the IP address, preferring the X-Forwarded-For header if present
    forwarded_for = request.headers.get("x-forwarded-for")
    ip_address = forwarded_for.split(",")[0].strip() if forwarded_for else request.client.host

    logger = RequestLogger(start_time, request.method, request.url, request.query_params, request.headers, ip_address)

    # Call the route handler to get the response
    response = await call_next(request)

    # Set user data if available
    if hasattr(request.state, "validation_data") and request.state.validation_data:
      login = request.state.validation_data.get('user', {}).get('login')
      if login:
        user_profile_id = request.state.validation_data.get('user', {}).get('userProfileId')
        user = f"{login}/{user_profile_id}"
        session_id = request.state.validation_data.get('user', {}).get('id')
        set_user_data('session_id', session_id)
        set_user_data('user', user)

    # If the Response is a StreamingResponse, wrap it as a generator to calculate the body length
    if hasattr(response, "body_iterator"):
      async def count_bytes_and_stream(generator):
        try:
          async for chunk in generator:
            logger.update_body_length(len(chunk))
            yield chunk
        finally:
          logger.calculate_response_time()
          logger.log(response.status_code)
      response.body_iterator = count_bytes_and_stream(response.body_iterator)
    else:
      logger.update_body_length(response.headers.get('content-length', 0))
      logger.calculate_response_time()
      logger.log(response.status_code)
    return response
  except HTTPException as exc:
    log_http_exception(exc, request)
    log_request_received(request)
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})
  except Exception as exc:
    log_generic_exception(exc, request)
    log_request_received(request)
    return JSONResponse(status_code=500, content={"detail": "Internal Server Error"})

# Generic TaskGroup exception handler
async def handle_task_group_exceptions(tasks):
  try:
    async with asyncio.TaskGroup() as task_group:
      for task in tasks:
        task_group.create_task(task())
  except Exception as exc:
    if isinstance(exc, ExceptionGroup):
      log_exception_group(exc)
    else:
      log_single_exception(exc)
    return {"status": "Task execution failed", "error": str(exc)}
  return {"status": "Tasks execution completed successfully"}

async def custom_security_headers_middleware(request: Request, call_next: callable):
  response = await call_next(request)

  # Remove Server header
  if "Server" in response.headers:
    del response.headers["Server"]

  response.headers["X-Content-Type-Options"] = "nosniff"
  response.headers["X-Frame-Options"] = "DENY"
  response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains; preload"
  response.headers["X-XSS-Protection"] = "1; mode=block"

  response.headers["Content-Security-Policy"] = (
    "default-src 'self'; "
    "script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.17.14/swagger-ui-bundle.js; "
    "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.17.14/swagger-ui.css; "
    "img-src 'self' data:; "
    "font-src 'self' data:; "
    "connect-src 'self';"
  )

  response.headers["Referrer-Policy"] = "no-referrer"

  return response
