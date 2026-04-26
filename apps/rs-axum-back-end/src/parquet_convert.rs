use axum::{
  body::Body,
  http::{StatusCode, header},
  extract::Multipart,
  response::Response,
};
use std::{
  fs::File,
  io::Write,
};
use tempfile::NamedTempFile;
use serde::Deserialize;
use serde_json;
use polars::prelude::*;

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
    let file = File::open(parquet_file.path()).map_err(|e| {
      JsonLogger::new().error(&format!("Error opening file: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let mut df = ParquetReader::new(file).finish().map_err(|e| {
      JsonLogger::new().error(&format!("Error reading parquet with Polars: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let path_buf = std::env::temp_dir().join(format!("arrow-out-{}.arrow", uuid::Uuid::new_v4()));
    let mut output_writer = File::create(&path_buf).map_err(|e| {
      JsonLogger::new().error(&format!("Error creating output file: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;

    IpcWriter::new(&mut output_writer).finish(&mut df).map_err(|e| {
      JsonLogger::new().error(&format!("Error writing IPC with Polars: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;

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

  Response::builder()
    .status(StatusCode::OK)
    .header(header::CONTENT_TYPE, "application/vnd.apache.arrow.file")
    .header(header::CONTENT_DISPOSITION, format!("attachment; filename=\"{}\"", file_name.replace(".parquet", ".arrow")))
    .body(body)
    .map_err(|e| {
      JsonLogger::new().error(&format!("Error building response: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })
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

  let file_name = field.file_name().unwrap_or("data.arrow").to_string();
  let data = field.bytes().await.map_err(|e| {
    logger.error(&format!("Error reading input file: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;

  let temp_arrow_path = std::env::temp_dir().join(format!("upload-{}.arrow", uuid::Uuid::new_v4()));
  let mut file = File::create(&temp_arrow_path).map_err(|e| {
    logger.error(&format!("Create temp file failed: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;

  file.write_all(&data).map_err(|e| {
    logger.error(&format!("Error writing chunk: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;

  logger.info(&format!("Local arrow file written: {:?}", &file_name), None);

  let temp_json_path = std::env::temp_dir().join(format!("converted-{}.ndjson", uuid::Uuid::new_v4()));
  
  {
    let arrow_reader = File::open(&temp_arrow_path).map_err(|e| {
      logger.error(&format!("Error opening Arrow file: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let mut df = IpcReader::new(arrow_reader).finish().map_err(|e| {
      logger.error(&format!("Error reading IPC with Polars: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let mut writer = File::create(&temp_json_path).map_err(|e| {
      logger.error(&format!("Create JSON file failed: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;

    JsonWriter::new(&mut writer).with_json_format(JsonFormat::JsonLines).finish(&mut df).map_err(|e| {
      logger.error(&format!("Error writing NDJSON with Polars: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;
  }

  logger.info(&format!("Local ndjson file written: {:?}", &file_name), None);
  
  // Clean up upload file
  let _ = tokio::fs::remove_file(&temp_arrow_path).await;

  let file = tokio::fs::File::open(&temp_json_path).await.map_err(|e| {
    logger.error(&format!("Open NDJSON for stream failed: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;
  let stream = ReaderStream::new(file);
  let body = Body::from_stream(stream);

  let cleanup_path = temp_json_path.clone();
  tokio::spawn(async move {
    tokio::time::sleep(tokio::time::Duration::from_secs(10)).await;
    let _ = tokio::fs::remove_file(cleanup_path).await;
  });

  Response::builder()
    .header(header::CONTENT_TYPE, "application/x-ndjson")
    .header(
      header::CONTENT_DISPOSITION,
      format!("attachment; filename=\"{}.ndjson\"", file_name.replace(".arrow", "")),
    )
    .body(body)
    .map_err(|e| {
      logger.error(&format!("Error building NDJSON response: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })
}
