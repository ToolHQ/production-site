import warnings
from elasticsearch import Elasticsearch, helpers
import pyarrow as pa
import pyarrow.parquet as pq
import os
import time
import json
from datetime import datetime

# Disable TLS InsecureRequestWarnings
warnings.filterwarnings('ignore', message='Unverified HTTPS request')

# Configuration for Elasticsearch
es = Elasticsearch(
    ['https://es.localhost'],
    basic_auth=(os.getenv('ELASTIC_USER'), os.getenv('ELASTIC_PASSWORD')),
    verify_certs=False
)

# Function to retrieve data from Elasticsearch using scroll API for low memory consumption
def fetch_data(index, scroll_time="2m", batch_size=1000):
    first_page = es.search(
        index=index,
        body={
            "query": {
                "match_all": {}
            },
            "sort": [
                {"@timestamp": {"order": "asc"}}
            ]
        },
        scroll=scroll_time,
        size=batch_size
    )

    sid = first_page['_scroll_id']
    scroll_size = len(first_page['hits']['hits'])

    total_hits = first_page['hits']['total']['value']
    processed_hits = 0

    while scroll_size > 0:
        # Yield the list of documents as a batch
        batch = [doc['_source'] for doc in first_page['hits']['hits']]
        processed_hits += len(batch)
        yield batch

        # Print progress for the Arrow file creation
        progress_percentage = (processed_hits / total_hits) * 100
        print(f"Arrow processing: {progress_percentage:.2f}% complete")

        # Get the next scroll page
        first_page = es.scroll(scroll_id=sid, scroll=scroll_time)
        sid = first_page['_scroll_id']
        scroll_size = len(first_page['hits']['hits'])

# Arrow schema definition for optimal compression
def create_arrow_schema():
    return pa.schema([
        # ('userLogin', pa.utf8()),
        ('userId', pa.int32()),
        # ('@timestamp', pa.timestamp('ms')),
        ('httpPath', pa.utf8()),
        ('httpMethod', pa.utf8()),
        ('httpQuery', pa.utf8()),
        # ('httpStatus', pa.int32()),
        # ('elapsedTime', pa.int32()),
        ('accountNumber', pa.utf8())
    ])

# Ensure each record matches the schema (convert types)
def normalize_record(record):
    try:
        # Log each integer conversion for better visibility
        user_id = to_int32(record.get('userId', 0))
        http_status = to_int32(record.get('httpStatus', 0))
        elapsed_time = to_int32(record.get('elapsedTime', 0))

        print(f"Normalizing record: userId={user_id}, httpStatus={http_status}, elapsedTime={elapsed_time}")

        return {
            # 'userLogin': str(record.get('userLogin', '')),
            # 'userId': user_id,  # Ensuring int32 compatibility
            'userId': record.get('userId', 0),  # Ensuring int32 compatibility
            # '@timestamp': parse_timestamp(record.get('@timestamp')),  # Convert ISO 8601 to Unix timestamp
            'httpPath': str(record.get('httpPath', '')),
            'httpMethod': str(record.get('httpMethod', '')),
            'httpQuery': str(record.get('httpQuery', '')) if record.get('httpQuery') is not None else "",
            # 'httpStatus': http_status,  # Ensuring int32 compatibility
            # 'elapsedTime': elapsed_time,  # Ensuring int32 compatibility
            'accountNumber': str(record.get('accountNumber', ''))
        }
    except Exception as e:
        print(f"Error normalizing record: {record}. Error: {e}")
        return None  # Skip problematic records


# Helper to parse timestamp string to actual timestamp (convert ISO 8601 string to Unix timestamp in milliseconds)
def parse_timestamp(ts):
    if ts is None:
        return None
    try:
        # Convert ISO 8601 string to datetime object and then to milliseconds
        dt = datetime.strptime(ts, '%Y-%m-%dT%H:%M:%S.%fZ')
        # Convert to Unix timestamp in milliseconds
        return int(dt.timestamp() * 1000)
    except ValueError as e:
        print(f"Timestamp parsing error: {ts}. Error: {e}")
        return None

# Helper to cast to int32 and handle errors
def to_int32(value):
    try:
        # Ensure that the value is an integer and falls within int32 range
        return int(value) if value is not None else 0
    except (ValueError, TypeError):
        print(f"Invalid int value encountered: {value}, defaulting to 0.")
        return 0

# Log the problematic record and the row number
def log_problematic_record(record, row_number):
    print(f"\nProblematic record at row {row_number}:")
    for key, value in record.items():
        print(f"Field '{key}' has type '{type(value).__name__}' with value '{value}'")

# Save data to Apache Arrow format
def save_to_arrow(data_gen, arrow_file):
    schema = create_arrow_schema()
    total_records = 0

    with pa.OSFile(arrow_file, 'wb') as sink:
        with pa.RecordBatchFileWriter(sink, schema) as writer:
            for batch_data in data_gen:
                normalized_batch = []
                for i, row in enumerate(batch_data):
                    normalized_record = normalize_record(row)
                    if normalized_record:
                        normalized_batch.append(normalized_record)

                if not normalized_batch:
                    print("Skipping empty or invalid batch.")
                    continue

                total_records += len(normalized_batch)
                print(f"Normalized batch contains {len(normalized_batch)} records.")

                # Convert the normalized batch to individual arrays (columns)
                try:
                    # user_logins = [row['userLogin'] for row in normalized_batch]
                    user_ids = [row['userId'] for row in normalized_batch]
                    http_paths = [row['httpPath'] for row in normalized_batch]
                    http_methods = [row['httpMethod'] for row in normalized_batch]
                    http_queries = [row['httpQuery'] for row in normalized_batch]
                    account_numbers = [row['accountNumber'] for row in normalized_batch]

                    # Create a RecordBatch directly
                    record_batch = pa.RecordBatch.from_arrays([
                        # pa.array(user_logins, pa.utf8()),
                        pa.array(user_ids, pa.int32()),
                        pa.array(http_paths, pa.utf8()),
                        pa.array(http_methods, pa.utf8()),
                        pa.array(http_queries, pa.utf8()),
                        pa.array(account_numbers, pa.utf8())
                    ], schema=schema)

                    # Write the RecordBatch instead of the whole table
                    writer.write_batch(record_batch)
                    print(f"Wrote batch with {record_batch.num_rows} rows.")

                except pa.ArrowInvalid as e:
                    print(f"Error writing batch: {e}")
                    break  # Stop after logging the error

    print(f"Arrow file written with {total_records} records.")



# Convert Arrow file to Parquet format with progress logging
def convert_to_parquet(arrow_file, parquet_file):
    # Read Arrow file
    try:
        table = pa.ipc.open_file(arrow_file).read_all()
        # Debugging: log row count and schema
        print(f"Arrow file read with {table.num_rows} rows and {table.num_columns} columns")
        print(f"Schema: {table.schema}")

        if table.num_rows == 0:
            print("Arrow file contains 0 rows. Exiting conversion.")
            return

        # Now proceed to Parquet conversion
        total_rows = table.num_rows
        batch_size = 10000

        with pq.ParquetWriter(parquet_file, table.schema, compression='SNAPPY', use_dictionary=True) as writer:
            for i in range(0, total_rows, batch_size):
                batch = table.slice(i, batch_size)
                writer.write_table(batch)
                progress_percentage = (i + batch.num_rows) / total_rows * 100
                print(f"Parquet processing: {progress_percentage:.2f}% complete")

        print(f"Parquet file written with {total_rows} rows.")
    except Exception as e:
        print(f"Failed to read Arrow file: {e}")


if __name__ == '__main__':
    index_name = 'logspoc'
    arrow_file = 'logs_data.arrow'
    parquet_file = 'logs_data.parquet'

    # Start time for logging
    start_time = time.time()

    # Stream data from Elasticsearch and save to Arrow file
    print("Fetching data from Elasticsearch and saving to Arrow format...")
    data_gen = fetch_data(index=index_name)
    save_to_arrow(data_gen, arrow_file)
    print(f"Data saved to Arrow file: {arrow_file}")

    # Convert Arrow file to Parquet file
    print("Converting Arrow file to Parquet format...")
    convert_to_parquet(arrow_file, parquet_file)
    print(f"Data converted to Parquet file: {parquet_file}")

    # End time and elapsed time logging
    end_time = time.time()
    elapsed_time_minutes = (end_time - start_time) / 60
    print(f"Process completed in {elapsed_time_minutes:.2f} minutes")
