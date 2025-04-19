use axum::{extract::Multipart, http::HeaderMap, response::IntoResponse, routing::post, Json, Router};
use std::{fs::File, io::Write, path::PathBuf};
use tempfile::{NamedTempFile, TempDir};
use tokio_util::io::ReaderStream;
use axum::response::Response;
use futures::StreamExt;
use uuid::Uuid;
use parquet2::read::read_metadata;
use parquet2::read::FileReader;
use parquet2::read::get_page_stream;
use arrow2::io::parquet::read::{infer_schema, FileReader as ArrowParquetReader};
use arrow2::io::ipc::write::{FileWriter, WriteOptions};
use utoipa::ToSchema;
use axum::extract::DefaultBodyLimit;

#[derive(ToSchema)]
pub struct UploadForm {}

pub fn routes() -> Router {
    Router::new().route("/convert-parquet-into-arrow", post(handler))
        .layer(DefaultBodyLimit::max(10 * 1024 * 1024 * 1024)) // up to 10GB
}

async fn handler(mut multipart: Multipart) -> Response {
    let Some(field) = multipart.next_field().await.unwrap_or(None) else {
        return Json("file is required").into_response();
    };

    let file_name = field.file_name().map(ToString::to_string).unwrap_or("upload.parquet".to_string());

    let temp_dir = TempDir::new().unwrap();
    let parquet_path = temp_dir.path().join(file_name);
    let mut file = File::create(&parquet_path).unwrap();
    let mut field_bytes = field.bytes().await.unwrap();
    while !field_bytes.is_empty() {
        file.write_all(&field_bytes).unwrap();
        if let Some(next) = multipart.next_field().await.unwrap_or(None) {
            field_bytes = next.bytes().await.unwrap();
        } else {
            break;
        }
    }

    // Generate .arrow file
    let arrow_path = temp_dir.path().join("converted.arrow");
    convert_parquet_to_arrow(&parquet_path, &arrow_path).unwrap();

    let stream = ReaderStream::new(tokio::fs::File::open(&arrow_path).await.unwrap());
    let body = axum::body::Body::from_stream(stream);

    let mut headers = HeaderMap::new();
    headers.insert("Content-Type", "application/octet-stream".parse().unwrap());
    headers.insert("Content-Disposition", format!("attachment; filename=converted.arrow").parse().unwrap());

    (headers, body).into_response()
}

fn convert_parquet_to_arrow(parquet_path: &PathBuf, arrow_path: &PathBuf) -> Result<(), Box<dyn std::error::Error>> {
    let mut parquet_file = File::open(parquet_path)?;
    let metadata = read_metadata(&mut parquet_file)?;
    let schema = infer_schema(&metadata)?;
    let reader = ArrowParquetReader::new(parquet_file, metadata.row_groups, schema, None, None);

    let mut arrow_file = File::create(arrow_path)?;
    let options = WriteOptions { compression: None }; // no compression
    let mut writer = FileWriter::try_new(&mut arrow_file, &reader.schema(), options)?;

    for maybe_batch in reader {
        let batch = maybe_batch?;
        writer.write(&batch, None)?;
    }
    writer.finish()?
}
