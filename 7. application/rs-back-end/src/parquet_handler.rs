use axum::{
    extract::Multipart,
    http::{header, StatusCode},
    response::{IntoResponse, Response},
};
use bytes::Bytes;
use futures::TryStreamExt;
use http_body::Frame;
use http_body_util::StreamBody;
use polars::prelude::{LazyFrame, AnyValue};
use serde::{Deserialize, Serialize};
use serde_json::Value;
// use tempfile::NamedTempFile;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tokio::io::AsyncWriteExt;
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
    let temp_path = std::env::temp_dir().join(format!("upload_{}.parquet", uuid::Uuid::new_v4()));
    let mut temp_file = tokio::fs::File::create(&temp_path).await.unwrap();

    while let Some(mut field) = multipart.next_field().await.unwrap() {
        while let Ok(Some(chunk)) = field.chunk().await {
            temp_file.write_all(&chunk).await.unwrap();
        }
    }

    temp_file.flush().await.unwrap();

    let (tx, rx) = mpsc::channel::<Result<Bytes, std::io::Error>>(1);

    tokio::spawn(async move {
        let _ = tx.send(Ok(Bytes::from_static(b"["))).await;

        let lf = LazyFrame::scan_parquet(temp_path.as_path().to_str().unwrap(), Default::default())
            .unwrap();

        let df = lf.collect().unwrap();
        let height = df.height();
        let column_names = df.get_column_names().to_vec(); // clone para soltar df depois

        for i in 0..height {
            let row = df.get_row(i).unwrap();

            let mut map = serde_json::Map::with_capacity(column_names.len());
            for (name, val) in column_names.iter().zip(row.0.iter()) {
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

            let json_line = serde_json::to_string(&Value::Object(map)).unwrap();
            let line = if i == 0 {
                json_line
            } else {
                format!(",{}", json_line)
            };
            tx.send(Ok(Bytes::from(line))).await.unwrap();
        }

        drop(df);
        let _ = tx.send(Ok(Bytes::from_static(b"]"))).await;
        drop(temp_file);
        let _ = tokio::fs::remove_file(&temp_path).await;
    });

    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "application/json")
        .body(StreamBody::new(ReceiverStream::new(rx).map_ok(Frame::data)))
        .unwrap()
}
