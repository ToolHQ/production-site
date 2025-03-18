import tempfile
import multiprocessing
from time import time
from datetime import timedelta
import asyncio
import os
import json
from concurrent.futures import ThreadPoolExecutor

from typing import Optional, List, Dict, Any
import boto3
import boto3.s3
import boto3.s3.constants
import botocore.exceptions
import duckdb
import pandas as pd
from boto3.s3.transfer import TransferConfig

from app.libs.logger import CustomLogger

from .parquet_common import next_item
from ..enrich_processor.db import simple_pre_consult_user_data

logger = CustomLogger("Generic DuckDB Parquet Processor")

progress_bar_disable_command = 'PRAGMA disable_progress_bar'

enriched_fields = [
  'userName',
  'accessProfile',
  'companyName'
]

def download_single_file_from_s3(s3_client, parquet_path: str, local_file_path: str):
  start_time = time()
  file_already_downloaded = os.path.exists(local_file_path)
  if not file_already_downloaded:
    bucket_name, key = parquet_path.replace('s3://', '').split('/', 1)
    config = TransferConfig(multipart_chunksize=256 * 1024 * 1024, max_concurrency=15)
    try:
      s3_client.download_file(bucket_name, key, local_file_path, Config=config)
    except botocore.exceptions.ClientError as e:
      if (not hasattr(e, 'response') or e.response['Error']['Code'] != '404'):
        logger.error({ "step": "botocore.exceptions.ClientError", "key": key, "error": str(e) })
      return None
    except Exception as e:
      logger.error({ "step": "Download failed", "key": key, "error": str(e) })
      return None
    logger.info({ "step": "Downloaded completed", "parquet_path": parquet_path })
  elapsed_time_ms = round((time() - start_time) * 1000, 3)
  logger.info({
    "step": "download_single_file_from_s3",
    "parquet_path": parquet_path,
    "timeElapsed": f"{elapsed_time_ms}ms",
    "file_already_downloaded": file_already_downloaded
  })
  return local_file_path

def download_files_from_s3(parquet_paths: List[str]) -> List[str]:
  ''' Download files from S3 (minio) '''
  s3_client = boto3.client(
    's3',
    endpoint_url=os.environ['MINIO_ENDPOINT'],
    aws_access_key_id=os.environ['MINIO_ACCESS_KEY'],
    aws_secret_access_key=os.environ['MINIO_SECRET_KEY']
  )
  local_files = []
  downloaded_files = []

  # Prepare download tasks
  tasks = []
  with ThreadPoolExecutor() as executor:
    for parquet_path in parquet_paths:
      local_file_path = f"/tmp/{'-'.join(parquet_path.split('/'))}"
      local_files.append(local_file_path)
      tasks.append(executor.submit(download_single_file_from_s3, s3_client, parquet_path, local_file_path))

    # Collect only successfully downloaded files
    downloaded_files = [task.result() for task in tasks if task.result() is not None]

  tasks.clear()
  executor.shutdown(wait=True)
  return downloaded_files

def sync_process_generic_raw_parquet_generator(
  parquet_paths: List[str],
  filters_optional: Dict[str, Any],
  filters_optional_strict: Dict[str, Any],
  limit: int,
  offset: int,
  columns_to_select: Optional[List[str]],
  sort_by: Optional[str],
  order: str,
  left_join_conditions: Optional[Dict[str, List[str]]] = None,
  timestamp_column: Optional[str] = 'timestamp',
):
  # Download parquet file(s) from S3 if not already downloaded
  local_file_paths = download_files_from_s3(parquet_paths)

  if not local_file_paths:
    logger.error({ "step": "files download step", "message": "No file downloaded" })
    yield '{"total": 0, "result": []}'
    return

  logger.info({ "step":  })
