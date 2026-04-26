use axum::{
    extract::Multipart,
    http::{header, StatusCode},
    response::{IntoResponse, Response},
};
use bytes::Bytes;
use futures::TryStreamExt;
use http_body::Frame;
use http_body_util::StreamBody;
use serde::{Deserialize, Serialize};
use serde_json::{Value};
use std::fs::File;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tokio::io::AsyncWriteExt;

use utoipa::ToSchema;
use polars::prelude::*;
use crate::logger::JsonLogger;

#[derive(Deserialize, ToSchema)]
pub struct UploadForm {
    /// Dummy field just to make Swagger render multipart/form-data
    #[allow(dead_code)]
    #[schema(format = Binary)]
    file: String,
}

#[derive(Serialize, ToSchema)]
pub struct JsonRowResponse {
    #[schema(value_type = Object)]
    row: Value,
}

#[utoipa::path(
    post,
    path = "/upload-parquet",
    request_body(
        description = "Upload a Parquet file",
        content = UploadForm,
        content_type = "multipart/form-data",
    ),
    responses((status = 200, description = "Streamed JSON rows", body = [JsonRowResponse])),
    tag = "Parquet"
)]
pub async fn upload_and_stream_parquet(mut multipart: Multipart) -> Result<impl IntoResponse, StatusCode> {
    let logger = JsonLogger::new();
    let mut temp_path = std::env::temp_dir();
    temp_path.push(format!(".tmp{}.parquet", uuid::Uuid::new_v4()));

    let mut parquet_file = tokio::fs::File::create(&temp_path).await.map_err(|e| {
        logger.error(&format!("Failed to create temp file: {:?}", e), None);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    while let Some(field) = multipart.next_field().await.map_err(|e| {
        logger.error(&format!("Failed to read multipart field: {:?}", e), None);
        StatusCode::BAD_REQUEST
    })? {
        let chunk = field.bytes().await.map_err(|e| {
            logger.error(&format!("Failed to read field bytes: {:?}", e), None);
            StatusCode::BAD_REQUEST
        })?;
        parquet_file.write_all(&chunk).await.map_err(|e| {
            logger.error(&format!("Failed to write chunk to temp file: {:?}", e), None);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    }
    parquet_file.flush().await.map_err(|e| {
        logger.error(&format!("Failed to flush temp file: {:?}", e), None);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let json_bytes = {
        let file = File::open(&temp_path).map_err(|e| {
            logger.error(&format!("Failed to open temp parquet file: {:?}", e), None);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
        let mut df = ParquetReader::new(file).finish().map_err(|e| {
            logger.error(&format!("Failed to read parquet with Polars: {:?}", e), None);
            StatusCode::UNPROCESSABLE_ENTITY
        })?;
        
        let mut buf = Vec::new();
        JsonWriter::new(&mut buf).with_json_format(JsonFormat::Json).finish(&mut df).map_err(|e| {
            logger.error(&format!("Failed to write JSON with Polars: {:?}", e), None);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
        buf
    };
    
    let (tx, rx) = mpsc::channel::<Result<Bytes, std::io::Error>>(8);

    tokio::spawn(async move {
        // Send the JSON bytes in chunks or all at once since we already buffered it
        let chunk_size = 64 * 1024;
        for chunk in json_bytes.chunks(chunk_size) {
            if tx.send(Ok(Bytes::copy_from_slice(chunk))).await.is_err() {
                break;
            }
        }
        let _ = tokio::fs::remove_file(&temp_path).await;
    });

    let body = StreamBody::new(ReceiverStream::new(rx).map_ok(Frame::data));
    Response::builder()
        .header(header::CONTENT_TYPE, "application/json")
        .body(body)
        .map_err(|e| {
            logger.error(&format!("Failed to build response: {:?}", e), None);
            StatusCode::INTERNAL_SERVER_ERROR
        })
}
