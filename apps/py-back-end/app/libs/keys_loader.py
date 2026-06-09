import os
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import boto3

from app.libs.logger import CustomLogger

keys_loader_load_logger = CustomLogger("KeysLoader USERNAME/PASSWORD loaded")
keys_loader_load_error_logger = CustomLogger("KeysLoader getDBCredentials ERROR")
keys_loader_decrypted_logger = CustomLogger("KeysLoader USERNAME/PASSWORD decrypted")
keys_loader_decrypt_error_logger = CustomLogger("KeysLoader decryptData ERROR")

# Initialize clients
dynamodb = boto3.resource("dynamodb")
kms = boto3.client("kms")

table_name = 'TB_KEYS'
table = dynamodb.Table(table_name)

def decrypt_password(encrypted_password):
  try:
    response = kms.decrypt(CiphertextBlob=encrypted_password)
    return response["Plaintext"].decode("utf-8")
  except Exception as e:
    keys_loader_decrypt_error_logger.error(f"Error decrypting password: {e}")
    return None

def get_db_credentials(key):
  # Fetch item from KeyStore
  start_time = time.time()
  response = table.get_item(Key={"KEY": key})
  elapsed_time_ms = round((time.time() - start_time) * 1000, 3)

  # Check if item exists
  if "Item" not in response:
    keys_loader_load_error_logger.error(f"Key {key} not found in {table_name}")
    return {
      "key": key,
      "status": "not found",
      "elapsed_time_ms": elapsed_time_ms,
    }

  item = response["Item"]

  # Logs the retrieval time
  keys_loader_load_logger.info({
    "sourceKey": key,
    "timeElapsed": f"{elapsed_time_ms}ms",
  })

  # Extract fields
  encrypted_password = item["PASSWORD"].value
  user = item["USER"]

  # Decrypt password
  start_time = time.time()
  decrypted_password = decrypt_password(encrypted_password)
  elapsed_time_ms = round((time.time() - start_time) * 1000, 3)

  if decrypted_password is None:
    keys_loader_decrypt_error_logger.error({
      "sourceKey": key,
      "timeElapsed": f"{elapsed_time_ms}ms",
    })
    return {
      "key": key,
      "status": "decryption failed",
      "elapsed_time_ms": elapsed_time_ms,
    }

  # Logs the decryption time
  keys_loader_decrypted_logger.info({
    "sourceKey": key,
    "timeElapsed": f"{elapsed_time_ms}ms",
  })

  # Set environment variables
  os.environ[f"{key}_USER"] = user
  os.environ[f"{key}_PASS"] = decrypted_password

  return {
    "key": key,
    "status": "success",
    "elapsed_time_ms": elapsed_time_ms,
  }

def load_credentials_environment():
  keys_string = os.getenv('KEYS_LOADER_KEYS', '')
  if not keys_string:
    keys_loader_load_error_logger.error("KEYS_LOADER_KEYS environment variable is empty.")
    return []

  keys = keys_string.split(',')

  results = []

  with ThreadPoolExecutor() as executor:
    futures = [executor.submit(get_db_credentials, key) for key in keys]
    for future in as_completed(futures):
      results.append(future.result())

  return results
