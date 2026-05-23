from fastapi import APIRouter

from .generic_parquet_route_builder import attach_parquet_routes

router = APIRouter(
)

attach_parquet_routes(
  router=router
)
