use axum::{
  body::{Body},
  http::{StatusCode, header},
  extract::Multipart,
  response::Response,
};
use std::{
  fs::File,
  io::{BufReader, Seek, SeekFrom, Write},
};
use tempfile::{NamedTempFile};
use parquet2::read::read_metadata;
use serde::{Deserialize};
use serde_json;
use arrow2::{
  array::{Array},
  chunk::Chunk,
  io::ipc::read::{read_file_metadata, FileReader as ArrowFileReader},
  io::parquet::read::{infer_schema, FileReader},
};
use futures_util::{StreamExt, TryStreamExt};

use tokio_util::io::ReaderStream;
use utoipa::ToSchema;

use crate::logger::JsonLogger;

#[derive(Deserialize, ToSchema)]
pub struct UploadForm {
  #[allow(dead_code)]
  #[schema(format = Binary)]
  file: String,
}

#[utoipa::path(
  post,
  path = "/convert-parquet-into-arrow",
  request_body(
    description = "Upload a Parquet file to convert to Arrow IPC format",
    content = UploadForm,
    content_type = "multipart/form-data",
  ),
  responses(
    (status = 200, description = "Arrow IPC file", content_type = "application/vnd.apache.arrow.file")
  ),
  tag = "Parquet"
)]
pub async fn convert_parquet_into_arrow(mut multipart: Multipart) -> Result<Response, StatusCode> {
  let field = match multipart.next_field().await {
    Ok(Some(field)) => field,
    Ok(None) => {
      JsonLogger::new().error("No file field received", None);
      return Err(StatusCode::BAD_REQUEST);
    }
    Err(e) => {
      JsonLogger::new().error(
        &format!("Error reading multipart field: {:?}", e),
        Some(serde_json::json!({ "component": "multipart" })),
      );
      return Err(StatusCode::BAD_REQUEST);
    }
  };

  let file_name = field.file_name().map(|f| f.to_string()).unwrap_or("converted.arrow".into());
  let data = field.bytes().await.map_err(|e| {
    JsonLogger::new().error(&format!("Error reading input file: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;

  let mut parquet_file = NamedTempFile::new().map_err(|e| {
    JsonLogger::new().error(&format!("Error creating temp file: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;

  parquet_file.write_all(&data).map_err(|e| {
    JsonLogger::new().error(&format!("Error writing to temp file: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;

  // convert into Arrow and store to persistent temp file path
  let arrow_file_path = {
    let mut reader = File::open(parquet_file.path()).map_err(|e| {
      JsonLogger::new().error(&format!("Error opening file: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let metadata = read_metadata(&mut reader).map_err(|e| {
      JsonLogger::new().error(&format!("Error reading metadata: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;

    reader.seek(SeekFrom::Start(0)).map_err(|e| {
      JsonLogger::new().error(&format!("Error seeking to start: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let schema = infer_schema(&metadata).map_err(|e| {
      JsonLogger::new().error(&format!("Error inferring schema: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let batches = FileReader::new(reader, metadata.row_groups, schema.clone(), None, None, None)
      .collect::<arrow2::error::Result<Vec<Chunk<Box<dyn Array>>>>>()
      .map_err(|e| {
        JsonLogger::new().error(&format!("Error reading Parquet record batches: {:?}", e), None);
        StatusCode::INTERNAL_SERVER_ERROR
      })?;

    let path_buf = std::env::temp_dir().join(format!("arrow-out-{}.arrow", uuid::Uuid::new_v4()));
    let mut output_writer = File::create(&path_buf).map_err(|e| {
      JsonLogger::new().error(&format!("Error creating output file: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let write_options = arrow2::io::ipc::write::WriteOptions { compression: None };
    let mut writer = arrow2::io::ipc::write::FileWriter::try_new(
      &mut output_writer,
      schema.clone(),
      None,
      write_options,
    ).map_err(|e| {
      JsonLogger::new().error(&format!("Error creating writer: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;

    for batch in batches {
      writer.write(&batch, None).map_err(|e| {
        JsonLogger::new().error(&format!("Error writing batch: {:?}", e), None);
        StatusCode::INTERNAL_SERVER_ERROR
      })?;
    }

    writer.finish().map_err(|e| {
      JsonLogger::new().error(&format!("Error finishing writer: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;

    drop(writer);
    drop(output_writer);
    path_buf
  };

  // Serve the file
  let file = tokio::fs::File::open(&arrow_file_path).await.map_err(|e| {
    JsonLogger::new().error(&format!("Error opening file: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;
  let stream = ReaderStream::new(file);
  let body = axum::body::Body::from_stream(stream);

  let cleanup_path = arrow_file_path.clone();
  tokio::spawn(async move {
    let _ = tokio::fs::remove_file(cleanup_path).await;
  });

  Ok(Response::builder()
    .status(StatusCode::OK)
    .header(header::CONTENT_TYPE, "application/vnd.apache.arrow.file")
    .header(header::CONTENT_DISPOSITION, format!("attachment; filename=\"{}\"", file_name.replace(".parquet", ".arrow")))
    .body(body)
    .unwrap())
}

#[utoipa::path(
  post,
  path = "/convert-arrow-into-ndjson",
  request_body(
    description = "Upload an Arrow IPC file to convert into JSON",
    content = UploadForm,
    content_type = "multipart/form-data",
  ),
  responses(
    (status = 200, description = "JSON file", content_type = "application/x-ndjson")
  ),
  tag = "Parquet"
)]
pub async fn convert_arrow_into_ndjson(mut multipart: Multipart) -> Result<Response, StatusCode> {
  let logger = JsonLogger::new();
  let Some(field) = multipart.next_field().await.map_err(|e| {
    logger.error(&format!("Error getting multipart field: {:?}", e), None);
    StatusCode::BAD_REQUEST
  })? else {
    logger.error("No file field found in multipart upload.", None);
    return Err(StatusCode::BAD_REQUEST);
  };
  // end-of-life: multipart

  let file_name = field.file_name().unwrap_or("data.arrow").to_string();
  let temp_arrow_path = std::env::temp_dir().join(format!("upload-{}.arrow", uuid::Uuid::new_v4()));
  let mut file = File::create(&temp_arrow_path).map_err(|e| {
    logger.error(&format!("Create temp file failed: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;
  let mut field_stream = field.into_stream(); // end-of-life: field

  while let Some(chunk) = field_stream.next().await {
    let data = chunk.map_err(|e| {
      logger.error(&format!("Error reading chunk: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;
    file.write_all(&data).map_err(|e| {
      logger.error(&format!("Error writing chunk: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;
  }

  drop(file);

  logger.info(&format!("Local arrow file written: {:?}", &file_name), None);

  let arrow_reader = File::open(&temp_arrow_path).map_err(|e| {
    logger.error(&format!("Error opening Arrow file: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;
  drop(temp_arrow_path);

  let mut reader = BufReader::new(arrow_reader);
  let metadata = read_file_metadata(&mut reader).map_err(|e| {
    logger.error(&format!("Metadata error: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;

  let file_reader = ArrowFileReader::new(reader, metadata, None, None);
  let schema = file_reader.schema().clone();

  let temp_json_path = std::env::temp_dir().join(format!("converted-{}.ndjson", uuid::Uuid::new_v4()));
  let mut writer = File::create(&temp_json_path).map_err(|e| {
    logger.error(&format!("Create JSON file failed: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;

  for maybe_batch in file_reader {
    let batch = maybe_batch.map_err(|e| {
      logger.error(&format!("Read batch error: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;
    let num_rows = batch.len();
    let step = 512;

    for offset in (0..num_rows).step_by(step) {
      let len = (offset + step).min(num_rows) - offset;
      let sliced = Chunk::<Box<dyn Array>>::new(
        batch
          .columns()
          .iter()
          .map(|col| col.as_ref().sliced(offset, len))
          .collect::<Vec<_>>(),
      );
      // now iterate `sliced` instead of `batch`
      // logger.info(&format!("Batch sliced length: {:?}", sliced.len()), None);
      for row_index in 0..sliced.len() {
        let mut map = serde_json::Map::new();
        for (col_index, field) in schema.fields.iter().enumerate() {
          // logger.info(&format!("Column {col_index}: {:?}", field.data_type()), None);
          let column = &sliced.columns()[col_index];
          let value: serde_json::Value = if let Some(arr) = column.as_any().downcast_ref::<arrow2::array::Utf8Array<i32>>() {
              arr.value(row_index).into()
            } else if let Some(arr) = column.as_any().downcast_ref::<arrow2::array::Int64Array>() {
              arr.value(row_index).into()
            } else if let Some(arr) = column.as_any().downcast_ref::<arrow2::array::Int32Array>() {
              arr.value(row_index).into()
            } else if let Some(arr) = column.as_any().downcast_ref::<arrow2::array::Int16Array>() {
              arr.value(row_index).into()
            } else if let Some(arr) = column.as_any().downcast_ref::<arrow2::array::Float64Array>() {
              arr.value(row_index).into()
            } else if let Some(arr) = column.as_any().downcast_ref::<arrow2::array::Float32Array>() {
              arr.value(row_index).into()
            } else if let Some(arr) = column.as_any().downcast_ref::<arrow2::array::BooleanArray>() {
              arr.value(row_index).into()
            } else {
              serde_json::Value::Null
            };
          map.insert(field.name.clone(), value);
        }
        let json = serde_json::Value::Object(map);
          writeln!(writer, "{}", json.to_string()).map_err(|e| {
          logger.error(&format!("Write line error: {:?}", e), None);
          StatusCode::INTERNAL_SERVER_ERROR
        })?;
      }
      writer.flush().ok(); // optional
      drop(sliced);
    }
    drop(batch);
  }

  writer.flush().map_err(|e| {
    logger.error(&format!("Final flush NDJSON failed: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;
  drop(writer);

  logger.info(&format!("Local ndjson file written: {:?}", &file_name), None);
  tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
  // Spike will begin after here

  let file = tokio::fs::File::open(&temp_json_path).await.map_err(|e| {
    logger.error(&format!("Open NDJSON for stream failed: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;
  let stream = ReaderStream::new(file);
  let body = Body::from_stream(stream);

  Ok(Response::builder()
    .header(header::CONTENT_TYPE, "application/x-ndjson")
    .header(
      header::CONTENT_DISPOSITION,
      format!("attachment; filename=\"{}.ndjson\"", file_name.replace(".arrow", "")),
    )
    .body(body)
    .unwrap())
}
