use axum::{
  body::Body,
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
  let Some(field) = multipart.next_field().await.map_err(|e| {
    JsonLogger::new().error(&format!("Error getting multipart field: {:?}", e), None);
    StatusCode::BAD_REQUEST
  })? else {
    JsonLogger::new().error("No file field found in multipart upload.", None);
    return Err(StatusCode::BAD_REQUEST);
  };

  let file_name = field.file_name().unwrap_or("data.arrow").to_string();
  let temp_arrow_path = std::env::temp_dir().join(format!("upload-{}.arrow", uuid::Uuid::new_v4()));
  let mut file = File::create(&temp_arrow_path).map_err(|e| {
    JsonLogger::new().error(&format!("Create temp file failed: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;
  let mut field_stream = field.into_stream();

  while let Some(chunk) = field_stream.next().await {
    let data = chunk.map_err(|e| {
      JsonLogger::new().error(&format!("Error reading chunk: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;
    file.write_all(&data).map_err(|e| {
      JsonLogger::new().error(&format!("Error writing chunk: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;
  }

  drop(file);

  let arrow_reader = File::open(&temp_arrow_path).map_err(|e| {
    JsonLogger::new().error(&format!("Error opening Arrow file: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;

  let mut reader = BufReader::new(arrow_reader);
  let metadata = read_file_metadata(&mut reader).map_err(|e| {
    JsonLogger::new().error(&format!("Metadata error: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;

  let file_reader = ArrowFileReader::new(reader, metadata, None, None);
  let schema = file_reader.schema().clone();

  let temp_json_path = std::env::temp_dir().join(format!("converted-{}.ndjson", uuid::Uuid::new_v4()));
  let mut writer = File::create(&temp_json_path).map_err(|e| {
    JsonLogger::new().error(&format!("Create JSON file failed: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;

  for maybe_batch in file_reader {
    let batch = maybe_batch.map_err(|e| {
      JsonLogger::new().error(&format!("Read batch error: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;

    for row_index in 0..batch.len() {
      let mut map = serde_json::Map::new();

      for (col_index, field) in schema.fields.iter().enumerate() {
        let column = &batch.columns()[col_index];
        let value = column.as_any()
          .downcast_ref::<arrow2::array::Utf8Array<i32>>()
          .map(|arr| arr.value(row_index).into())
          .or_else(|| {
            column
              .as_any()
              .downcast_ref::<arrow2::array::Int64Array>()
              .map(|arr| arr.value(row_index).into())
          })
          .or_else(|| {
            column
              .as_any()
              .downcast_ref::<arrow2::array::BooleanArray>()
              .map(|arr| arr.value(row_index).into())
          });

        if let Some(v) = value {
          map.insert(field.name.clone(), v);
        }
      }

      let json = serde_json::Value::Object(map);
      writeln!(writer, "{}", json.to_string()).map_err(|e| {
        JsonLogger::new().error(&format!("Write line error: {:?}", e), None);
        StatusCode::INTERNAL_SERVER_ERROR
      })?;
    }
  }

  drop(writer);

  let final_reader = tokio::fs::File::open(&temp_json_path).await.map_err(|e| {
    JsonLogger::new().error(&format!("Open NDJSON for stream failed: {:?}", e), None);
    StatusCode::INTERNAL_SERVER_ERROR
  })?;

  let stream = ReaderStream::new(final_reader);
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
