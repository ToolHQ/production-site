use axum::{
  extract::Multipart,
  response::Response,
};
use std::{
  fs::File,
  io::{Seek, SeekFrom, Write},
};
use tempfile::NamedTempFile;
use parquet2::read::read_metadata;
use serde::{Deserialize};
use arrow2::{
  array::Array,
  chunk::Chunk,
  io::parquet::read::{infer_schema, FileReader},
  io::ipc::write::{FileWriter as ArrowFileWriter, WriteOptions as ArrowWriteOptions},
};
use axum::http::{header, StatusCode};
use tokio_util::io::ReaderStream;
use utoipa::ToSchema;

#[derive(Deserialize, ToSchema)]
pub struct UploadForm {
    /// Dummy field just to make Swagger render multipart/form-data
    #[allow(dead_code)]
    #[schema(format = Binary)]
    file: String,
}

#[utoipa::path(
  post,
  path = "/convert-parquet-into-arrow",
  request_body(
      description = "Upload a Parquet file",
      content = UploadForm,
      content_type = "multipart/form-data",
  ),
  responses(
    (status = 200, description = "Arrow IPC file", content_type = "application/vnd.apache.arrow.file")
  ),
  tag = "Parquet"
)]
pub async fn convert_parquet_into_arrow(mut multipart: Multipart) -> Result<Response, StatusCode> {
  let Some(field) = multipart.next_field().await.unwrap() else {
    return Err(StatusCode::BAD_REQUEST);
  };
  let file_name = field.file_name().map(|f| f.to_string()).unwrap_or("converted.arrow".into());
  let data = field.bytes().await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
  let mut parquet_file = NamedTempFile::new().map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
  parquet_file.write_all(&data).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
  let mut reader = File::open(parquet_file.path()).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
  let metadata = read_metadata(&mut reader).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
  reader.seek(SeekFrom::Start(0)).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
  let schema = infer_schema(&metadata).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
  let file_reader = FileReader::new(reader, metadata.row_groups, schema.clone(), None, None, None);
  let batches = file_reader.collect::<arrow2::error::Result<Vec<Chunk<Box<dyn Array>>>>>()
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
  let output_file = NamedTempFile::new().map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
  let mut output_writer = File::create(output_file.path()).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
  let write_options = ArrowWriteOptions { compression: None };
  let mut writer = ArrowFileWriter::try_new(
    &mut output_writer,
    schema.clone(),
    None, // ← let Arrow infer IPC fields
    write_options,
  ).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
  for batch in batches {
    writer.write(&batch, None).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
  }
  writer.finish().map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
  let file = tokio::fs::File::open(output_file.path()).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
  let stream = ReaderStream::new(file);
  let body = axum::body::Body::from_stream(stream);
  Ok(Response::builder()
    .status(StatusCode::OK)
    .header(header::CONTENT_TYPE, "application/vnd.apache.arrow.file")
    .header(header::CONTENT_DISPOSITION, format!("attachment; filename=\"{}\"", file_name.replace(".parquet", ".arrow")))
    .body(body)
    .unwrap())
}
