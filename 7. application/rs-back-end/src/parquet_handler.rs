use std::io::BufReader;

use axum::{
    extract::Multipart,
    response::IntoResponse,
    response::Response,
    http::{header, StatusCode},
};
use http_body::Frame;
use http_body_util::StreamBody;
use futures::TryStreamExt;

use bytes::Bytes;
use polars::prelude::*;
use polars::prelude::AnyValue;
use serde::{Serialize, Deserialize};
use serde_json::{Value};
use tempfile::NamedTempFile;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use utoipa::ToSchema;

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
pub async fn upload_and_stream_parquet(mut multipart: Multipart) -> impl IntoResponse {
    let mut temp_file = NamedTempFile::new().unwrap();

    while let Some(field) = multipart.next_field().await.unwrap() {
        let data = field.bytes().await.unwrap();
        std::io::copy(&mut data.as_ref(), &mut temp_file).unwrap();
    }

    let (tx, rx) = mpsc::channel::<Result<bytes::Bytes, std::io::Error>>(1);
    tokio::spawn(async move {
        let _ = tx.send(Ok(Bytes::from_static(b"["))).await;

        let file = std::fs::File::open(temp_file.path()).unwrap();
        let reader = ParquetReader::new(BufReader::new(file));
        let df = reader.finish().unwrap();

        for i in 0..df.height() {
            let row = df.get_row(i).unwrap(); // Polars row
            let mut map = serde_json::Map::new();
            for (name, val) in df.get_column_names().iter().zip(row.0.iter()) {
                let value = match val {
                    AnyValue::Null => Value::Null,
                    AnyValue::Boolean(b) => Value::from(*b),
                    AnyValue::Int32(i) => Value::from(*i),
                    AnyValue::Int64(i) => Value::from(*i),
                    AnyValue::Float64(f) => Value::from(*f),
                    AnyValue::String(s) => Value::from(*s),
                    _ => Value::String(val.to_string()),
                };
                map.insert(name.to_string(), value);
            }

            let json_str = serde_json::to_vec(&Value::Object(map)).unwrap();
            let json_line = String::from_utf8(json_str).unwrap(); // ✅ agora é String
            let line = if i == 0 {
                json_line
            } else {
                format!(",{}", json_line)
            };
            tx.send(Ok(Bytes::from(line))).await.unwrap();
        }

        let _ = tx.send(Ok(Bytes::from_static(b"]"))).await;
        // drop(df); // força desalocação
        drop(df);
    });
    // Response::new(StreamBody::new(ReceiverStream::new(rx).map_ok(Frame::data)))
    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "application/json")
        .body(StreamBody::new(ReceiverStream::new(rx).map_ok(Frame::data)))
        .unwrap()
}
