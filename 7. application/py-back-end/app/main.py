import os
from fastapi import FastAPI
from fastapi.openapi.docs import get_swagger_ui_html
from fastapi.openapi.utils import get_openapi
from fastapi.staticfiles import StaticFiles
from app.libs.middleware import request_logger_middleware, custom_security_headers_middleware
from .routes import database #, parquet

from app.libs.keys_loader import load_credentials_environment

# load_credentials_environment()

swagger_root_path = os.getenv("SWAGGER_ROOT_PATH", "")

app = FastAPI(
  openapi_url=f"{swagger_root_path}/openapi.json",
  docs_url=None,
  redoc_url=None,
)

def custom_openapi():
  if app.openapi_schema:
    return app.openapi_schema

  openapi_schema = get_openapi(
    title="MySite - Metrics API",
    description="Metrics API. Should be used to retrieve metrics data.",
    version="1.0.0",
    routes=app.routes,
  )

  openapi_schema["components"]["securitySchemes"] = {
    "APIKeyHeader": {
      "type": "apiKey",
      "name": "Authorization",
      "in": "header",
      "description": "Provide the token directly in the header.",
    }
  }

  openapi_schema["security"] = [{"APIKeyHeader": []}]

  openapi_schema["servers"] = [
    { "url": "/" },
    { "url": "/api/py" },
  ]
  app.openapi_schema = openapi_schema
  return app.openapi_schema

# app.openapi = custom_openapi

app.middleware("http")(request_logger_middleware)
app.middleware("http")(custom_security_headers_middleware)

# app.include_router(parquet.router)
app.include_router(database.router)

app.mount("/static", StaticFiles(directory="/app/app/static"), name="static")

@app.get("/swagger-ui", include_in_schema=False, description="Swagger UI for the API.")
async def custom_swagger_ui():
  return get_swagger_ui_html(
    openapi_url=app.openapi_url,
    title="MySite - Metrics API - Swagger UI",
    swagger_ui_parameters=app.swagger_ui_parameters,
    swagger_favicon_url='/static/favicon.ico',
    swagger_js_url="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.17.14/swagger-ui-bundle.js",
    swagger_css_url="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.17.14/swagger-ui.css",
  )

# Serve the OpenAPI schema
@app.get("/openapi.json", include_in_schema=False)
async def get_openapi_schema():
  return app.openapi()

@app.get("/health", include_in_schema=False, description="Health check endpoint to verify if the API is running properly.")
async def health_check():
  return {"status": "OK"}
