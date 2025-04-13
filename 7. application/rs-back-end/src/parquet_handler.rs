use axum::{
    extract::Multipart,
    response::IntoResponse,
    response::Response,
};

use bytes::Bytes;
use polars::prelude::*;
use polars::prelude::AnyValue;
use serde::{Serialize, Deserialize};
use serde_json::{Map, Value};
use std::{
    fs::File,
    io::Write,
};
use tempfile::NamedTempFile;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use utoipa::ToSchema;

#[derive(Deserialize, ToSchema)]
pub struct UploadForm {
    /// The file to upload
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
pub async fn upload_and_stream_parquet(mut multipart: Multipart) -> impl IntoResponse {
    let mut temp_file = NamedTempFile::new().unwrap();

    while let Some(field) = multipart.next_field().await.unwrap() {
        let data = field.bytes().await.unwrap();
        temp_file.write_all(&data).unwrap();
    }

    let file = File::open(temp_file.path()).unwrap();
    let df = ParquetReader::new(file).finish().unwrap();

    let (tx, rx) = mpsc::channel::<Result<Bytes, std::io::Error>>(10);

    tokio::spawn(async move {
        for idx in 0..df.height() {
            let row = df.get_row(idx).unwrap();
            let mut map = Map::new();

            for (i, name) in df.get_column_names().iter().enumerate() {
                let val = &row.0[i];
                let json_val = match val {
                    AnyValue::Null => Value::Null,
                    AnyValue::Boolean(b) => Value::from(*b),
                    AnyValue::Int32(i) => Value::from(*i),
                    AnyValue::Int64(i) => Value::from(*i),
                    AnyValue::Float64(f) => Value::from(*f),
                    AnyValue::String(s) => Value::from(*s),
                    _ => Value::String(val.to_string()),
                };
                map.insert(name.to_string(), json_val);
            }

            let json = serde_json::to_string(&map).unwrap() + "\n";
            if tx.send(Ok(Bytes::from(json))).await.is_err() {
                break;
            }
        }
    });

    Response::builder()
        .header("Content-Type", "application/json")
        .body(axum::body::Body::from_stream(ReceiverStream::new(rx)))
        .unwrap()
}
