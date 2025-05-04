import os
from datetime import datetime, timedelta

bucket_name = os.environ['PARQUET_S3_BUCKET']

def next_item(generator):
  try:
    return next(generator)
  except StopIteration:
    return None

def get_parquet_paths(eventTimestampMin: datetime, eventTimestampMax: datetime, parquet_type: str = 'BackEndRawLogs'):
  paths = []
  current_date = eventTimestampMin
  while current_date <= eventTimestampMax:
    year = current_date.year
    month = f"{current_date.month:02d}"
    day = f"{current_date.day:02d}"
    paths.append(f"{bucket_name}/raw/{year}/{month}/{day}/{parquet_type}.parquet")
    current_date += timedelta(days=1)
  return paths
