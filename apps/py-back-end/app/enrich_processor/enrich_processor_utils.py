from datetime import datetime, timedelta
from typing import List, TypedDict, Optional
from typeguard import typechecked

@typechecked
def add_days(date: datetime, days: int) -> datetime:
  ''' Adds days to a date '''
  return date + timedelta(days=days)

@typechecked
def concat_optional_strings(str1: Optional[str], str2: Optional[str]) -> str:
  ''' Concatenates two strings '''
  return f"{str1}{str2}" if str1 and str2 else str1 or str2 or ""

class JtiLoginDict(TypedDict):
  jti: Optional[str]
  loginAt: datetime

JtiLoginAtList = List[JtiLoginDict]

@typechecked
def concat_optional_session_datas(session_data1: Optional[JtiLoginAtList], session_data2: Optional[JtiLoginAtList]) -> JtiLoginAtList:
  ''' Concatenates two session data dictionaries '''
  sessionData1HasElementsWithJti = session_data1 is not None and any(
    sessionData1Element.get("jti") is not None for sessionData1Element in session_data1
  )
  sessionData2HasElementsWithJti = session_data2 is not None and any(
    sessionData2Element.get("jti") is not None for sessionData2Element in session_data2
  )
  print(sessionData1HasElementsWithJti, sessionData2HasElementsWithJti)
  if sessionData1HasElementsWithJti and sessionData2HasElementsWithJti:
    return session_data1 + session_data2
  return session_data1 if sessionData1HasElementsWithJti else session_data2 if sessionData2HasElementsWithJti else []


