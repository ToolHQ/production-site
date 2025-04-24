use axum::{
  extract::Multipart,
  response::Response,
};
use std::{
  fs::File,
  io::{Seek, SeekFrom, Write},
};
use tempfile::{NamedTempFile};
use parquet2::read::read_metadata;
use serde::{Deserialize};
use serde_json::json;
use arrow2::{
  array::Array,
  chunk::Chunk,
  io::parquet::read::{infer_schema, FileReader},
  io::ipc::write::{FileWriter as ArrowFileWriter, WriteOptions as ArrowWriteOptions},
};
use axum::http::{header, StatusCode};
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
        Some(json!({ "component": "multipart" })),
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

    let write_options = ArrowWriteOptions { compression: None };
    let mut writer = ArrowFileWriter::try_new(
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

  // Optional cleanup of file after response begins
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
