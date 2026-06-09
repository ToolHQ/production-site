import os
import httpx
import asyncio

from fastapi import Request, HTTPException, Depends
from fastapi.security import APIKeyHeader
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.libs.logger import CustomLogger, set_user_data

# Define custom HTTP scheme without the "Bearer" prefix
class CustomHTTPAuthorization(HTTPBearer):
  async def __call__(self, request):
    credentials: HTTPAuthorizationCredentials = await super().__call__(request)
    if not credentials:
      return HTTPException(status_code=403, detail="Invalid authorization header")
    return credentials.credentials

custom_security = CustomHTTPAuthorization()

SERVICE_NAME = os.getenv("SERVICE_NAME", "default-service")
AUTH_SERVICE = os.getenv("AUTH_SERVICE", "default-auth-service")

route_map = None

# Headers to exclude when forwarding request
EXCLUDED_HEADERS = [
  'accept',
  'accept-charset',
  'accept-datetime',
  'accept-encoding',
  'accept-language',
  'access-control-request-headers',
  'access-control-request-method',
  'cache-control',
  'connection',
  'content-encoding',
  'content-length',
  'content-type',
  'expect',
  'host',
  'range',
  'upgrade',
  'transfer-encoding',
]

logger = CustomLogger('authentication_middleware')
authorization_middleware_error_logger = CustomLogger('authorizationMiddleware ERROR')

api_key_header = APIKeyHeader(name="Authorization", auto_error=False)

async def post_with_retries(url, headers, body, retries=3, backoff_factor=0.5):
  timeout = httpx.Timeout(10.0)
  for attempt in range(retries):
    try:
      async with httpx.AsyncClient(timeout=timeout) as client:
        response = await client.post(url, headers=headers, data=body)
        return response
    except (httpx.ConnectTimeout, httpx.ReadTimeout):
      if attempt < retries - 1:
        await asyncio.sleep(backoff_factor * (2 ** attempt))
      else:
        raise
  return None

async def get_with_retries(url, headers, retries=3, backoff_factor=0.5):
  timeout = httpx.Timeout(10.0)
  for attempt in range(retries):
    try:
      async with httpx.AsyncClient(timeout=timeout) as client:
        response = await client.get(url, headers=headers)
        return response
    except (httpx.ConnectTimeout, httpx.ReadTimeout):
      if attempt < retries - 1:
        await asyncio.sleep(backoff_factor * (2 ** attempt))
      else:
        raise
  return None

async def get_route_map():
  global route_map
  if route_map is None:
    try:
      py_metrics_route_map = await get_with_retries(
        url=f"{AUTH_SERVICE}/route-map/{SERVICE_NAME}",
        headers={}
      )
      register_route_map = await get_with_retries(
        url=f"{AUTH_SERVICE}/route-map/my-site-register-back-end",
        headers={}
      )
      py_metrics_route_map_dict = py_metrics_route_map.json()
      register_route_map_dict = register_route_map.json()
      register_route_map_dict = {
        key.replace('/register', '/parquet', 1): value
        for key, value in register_route_map_dict.items()
        if key.startswith('/register/dataLog')
      }
      route_map = {**register_route_map_dict, **py_metrics_route_map_dict}
    except httpx.RequestError as e:
      logger.log_httpx_exception(e)
      raise HTTPException(status_code=500, detail="Failed to fetch route map")
  return route_map

async def authorization_dependency(request: Request, api_key: str = Depends(api_key_header)):
  """Authorization validation as a dependency for specific routes."""
  authorization = api_key
  if not authorization:
    raise HTTPException(status_code=400, detail="Invalid authorization header")

  forward_headers = {
    k: v for k, v in request.headers.items() if k.lower() not in EXCLUDED_HEADERS
  }

  body = {
    "route": f"{SERVICE_NAME},{request.method.upper()},{request.url.path}",
  }

  try:
    validation_response = await post_with_retries(
      url=f"{AUTH_SERVICE}/validate",
      headers=forward_headers,
      body=body
    )
  except httpx.RequestError as e:
    logger.log_httpx_exception(e)
    raise HTTPException(status_code=500, detail="Failed to validate authorization")

  validation_headers = {
    k: v for k, v in validation_response.headers.items() if k.lower().startswith('x-ms-')
  }

  if validation_response.status_code != 200:
    response = HTTPException(
      status_code=validation_response.status_code, detail="Authentication failed"
    )
    if (response.headers is None):
      response.headers = {}
    for key, value in validation_headers.items():
      response.headers[key] = value
    # response_error = validation_response.json()
    # if response_error:
    #   response.headers['x-ms-error-code'] = response_error
    authorization_middleware_error_logger.error({
        "status_code": validation_response.status_code,
        "response": validation_response.text.startswith('{') and validation_response.json() or validation_response.text,
        "headers": validation_headers,
    })
    raise response

  # Store validation data in request state
  request.state.validation_data = validation_response.json()
  if hasattr(request.state, "validation_data") and request.state.validation_data:
    login = request.state.validation_data.get('user', {}).get('login')
    if login:
      user_profile_id = request.state.validation_data.get('user', {}).get('userProfileId')
      user = f"{login}/{user_profile_id}"
      session_id = request.state.validation_data.get('user', {}).get('id')
      set_user_data('session_id', session_id)
      set_user_data('user', user)

  route_map = await get_route_map()
  validation_path = request.scope.get('path')
  validation_method = request.scope.get('method')
  route_permissions = route_map.get(validation_path, {}).get(validation_method, [])
  user_permissions_set = set(request.state.validation_data.get('permissions', []))
  has_permissions = any(permission in user_permissions_set for permission in route_permissions)
  if not has_permissions:
    raise HTTPException(status_code=403, detail="Unauthorized")

  return validation_headers

authentication_fast_api_dependencies = [Depends(api_key_header), Depends(authorization_dependency)]
