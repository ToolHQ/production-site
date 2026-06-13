from datetime import datetime
from typing import Dict, TypedDict
from typeguard import typechecked

from app.libs.db_wrapper import get_connection
from .enrich_processor_utils import add_days, concat_optional_strings, concat_optional_session_datas

def get_sessions (login_audit_id: str):
  db_connection = get_connection(
    host_env="DB_DNORIO_POSTGRES_HOST",
    port_env="DB_DNORIO_POSTGRES_PORT",
    database_env="DB_DNORIO_POSTGRES_DATABASE",
    creds_env="DB_DNORIO_POSTGRES",
    search_path_env="DB_DNORIO_POSTGRES_SCHEMA"
  )
  result = db_connection.execute_raw_query_with_logging(
'''select
  "id" as "jti",
  "created_at" as "createdAt",
from "tb_login_audit"
where "id" = :login_audit_id
limit 1''',
    {"login_audit_id": login_audit_id}
  )
  sessions = []
  for row in result:
    sessions.append(dict(row._mapping))
  return sessions

class UserData(TypedDict):
  userProfileId: str
  userLogin: str
  userName: str
  accessProfile: str
  companyName: str

SimpleUserDataDict = Dict[str, UserData]

@typechecked
def simple_pre_consult_user_data():
  db_connection = get_connection(
    host_env="DB_DNORIO_POSTGRES_HOST",
    port_env="DB_DNORIO_POSTGRES_PORT",
    database_env="DB_DNORIO_POSTGRES_DATABASE",
    creds_env="DB_DNORIO_POSTGRES",
    search_path_env="DB_DNORIO_POSTGRES_SCHEMA"
  )
  extract_query = '''select
  tb_user_profile.id as "userProfileId",
  tb_user_profile.user_login as "userLogin",
  tb_user_profile.user_name as "userName",
  tb_user_profile.access_profile as "accessProfile",
  tb_user_profile.company_name as "companyName"
from tb_user_profile
'''
  result = db_connection.execute_raw_query_with_logging(query=extract_query)
  mapped_result = {}
  for row in result:
    raw_user_data = dict(row._mapping)
    mapped_result[str(raw_user_data.get("userProfileId"))] = {
      "userProfileId": raw_user_data.get("userProfileId"),
      "userLogin": raw_user_data.get("userLogin"),
      "userName": raw_user_data.get("userName"),
      "accessProfile": raw_user_data.get("accessProfile"),
      "companyName": raw_user_data.get("companyName")
    }
  return mapped_result

@typechecked
def pre_consult_user_data (reference_date: datetime):
  lower_date = f"{add_days(reference_date, -3).strftime('%Y-%m-%d')}"
  upper_date = f"{add_days(reference_date, 3).strftime('%Y-%m-%d')}"
  db_connection = get_connection(
    host_env="DB_DNORIO_POSTGRES_HOST",
    port_env="DB_DNORIO_POSTGRES_PORT",
    database_env="DB_DNORIO_POSTGRES_DATABASE",
    creds_env="DB_DNORIO_POSTGRES",
    search_path_env="DB_DNORIO_POSTGRES_SCHEMA"
  )
  extract_query = '''with "base_user_data" as (
  select
    tb_user_profile.id as "userProfileId",
    tb_user_profile.user_login as "userLogin",
    tb_user_profile.user_name as "userName",
    tb_user_profile.access_profile as "accessProfile",
    tb_user_profile.company_name as "companyName"
  from tb_user_profile
)
select
  "base_user_data"."userProfileId",
  "base_user_data"."userLogin",
  "base_user_data"."userName",
  "base_user_data"."accessProfile",
  "base_user_data"."companyName",
  array_agg(
    json_build_object(
      'loginAt', "tb_login_audit"."created_at",
      'jti', "tb_login_audit"."id"
    )
  ) "possibleLoginsForCurrentPeriod"
from "base_user_data"
left join "tb_login_audit" on "base_user_data"."userProfileId" = "tb_login_audit"."user_profile_id"
where "tb_login_audit"."created_at" between :lower_date and :upper_date
group by
  "base_user_data"."userProfileId",
  "base_user_data"."userLogin",
  "base_user_data"."userName",
  "base_user_data"."accessProfile",
  "base_user_data"."companyName"
'''
  result = db_connection.execute_raw_query_with_logging(
    query=extract_query,
    params={"lower_date": lower_date, "upper_date": upper_date}
  )
  mapped_result = {}

  for row in result:
    raw_user_data = dict(row._mapping)
    user_data = {
      **raw_user_data,
      "possibleLoginsForCurrentPeriod": list(
        map(
          lambda x: {
            "loginAt": datetime.strptime(x["loginAt"], "%Y-%m-%d %H:%M:%S"),
            "jti": x["jti"]
          },
          raw_user_data.get("possibleLoginsForCurrentPeriod")
        )
      )
    }
    mapped_result[str(user_data.get("userProfileId"))] = user_data
    if (mapped_result.get(user_data.get("userLogin")) is not None):
      user_data_from_map = mapped_result.get(user_data.get("userLogin"))
      new_user_data = {
        "userLogin": user_data.get("userLogin"),
        "userName": user_data.get("userName"),
        "userProfileId": f"{user_data_from_map.get('userProfileId')},{user_data.get('userProfileId')}",
        "accessProfile": concat_optional_strings(user_data_from_map.get("accessProfile"), user_data.get("accessProfile")),
        "companyName": concat_optional_strings(user_data_from_map.get("companyName"), user_data.get("companyName")),
        "possibleLoginsForCurrentPeriod": concat_optional_session_datas(user_data_from_map.get("possibleLoginsForCurrentPeriod"), user_data.get("possibleLoginsForCurrentPeriod"))
      }
      mapped_result[user_data.get("userLogin")] = new_user_data
    else:
      mapped_result[user_data.get("userLogin")] = user_data
  return mapped_result
