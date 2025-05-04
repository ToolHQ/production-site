from fastapi import APIRouter
from app.libs.authentication_middleware import authentication_fast_api_dependencies

from .parquet_configs import (
  back_end_raw_logs_schema,
  back_end_query_params,
)

from .generic_parquet_route_builder import attach_parquet_routes

router = APIRouter(
#   dependencies=authentication_fast_api_dependencies
)

attach_parquet_routes(
  router=router
)
