from datetime import datetime
from fastapi import APIRouter, Query, Request
from typing import Optional

# from app.libs.authentication_middleware import authentication_fast_api_dependencies
from app.libs.logger import CustomLogger
from app.libs.db_wrapper import get_connection

from ..enrich_processor.db import get_sessions, pre_consult_user_data

db_logger = CustomLogger("Database Test")

router = APIRouter(
  tags=["Database Test"],
#   dependencies=authentication_fast_api_dependencies
)

# Group: "Database Test"
@router.get("/database-test", description="Test some queries at database")
async def database_test(
  request: Request,
  q: str,
  part: Optional[str] = Query(None, description="Comma-separated columns to be returned"),
  limit: Optional[int] = Query(25, description="Limit of rows to be returned"),
  offset: Optional[int] = Query(0, description="Offset of rows to be returned"),
):
  db_connection = get_connection(
    host_env="DB_DNORIO_POSTGRES_HOST",
    port_env="DB_DNORIO_POSTGRES_PORT",
    database_env="DB_DNORIO_POSTGRES_DATABASE",
    creds_env="DB_DNORIO_POSTGRES",
    search_path_env="DB_DNORIO_POSTGRES_SCHEMA"
  )
  result = db_connection.execute_raw_query_with_logging('SELECT * FROM tb_user_profile limit :limit offset :offset', {"limit": limit, "offset": offset})
  users = []
  for row in result:
    users.append(dict(row._mapping))
  return {
    "total": len(users),
    "rows": users
  }

@router.get("/database-test/sessions", description="Test query enrich_processor/db.py#get_sessions")
async def database_test_sessions(
  login_audit_id: str
):
  return get_sessions(login_audit_id)

@router.get("/database-test/pre-consult-user-data", description="Test query enrich_processor/db.py#pre_consult_user_data")
async def database_test_pre_consult_user_data(
  reference_date: datetime = Query(None, description="Reference date to filter the data")
):
  return pre_consult_user_data(reference_date)
