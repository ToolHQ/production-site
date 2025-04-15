use axum::{
    extract::Multipart,
    http::{header},
    response::{IntoResponse, Response},
};
use bytes::Bytes;
use futures::TryStreamExt;
use http_body::Frame;
use http_body_util::StreamBody;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::{
    fs::File,
};
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tokio::io::AsyncWriteExt;

use utoipa::ToSchema;

use arrow2::{
    array::{Utf8Array, PrimitiveArray},
    datatypes::{DataType},
};
use arrow2::io::parquet::read::{read_metadata as read_parquet_metadata, infer_schema, FileReader};

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
    let mut temp_path = std::env::temp_dir();
    temp_path.push(format!(".tmp{}.parquet", uuid::Uuid::new_v4()));

    let mut parquet_file = tokio::fs::File::create(&temp_path).await.unwrap();
    while let Some(field) = multipart.next_field().await.unwrap() {
        let chunk = field.bytes().await.unwrap();
        parquet_file.write_all(&chunk).await.unwrap();
    }
    parquet_file.flush().await.unwrap();

    let file = File::open(&temp_path).unwrap();
    let metadata = read_parquet_metadata(&mut file.try_clone().unwrap()).unwrap();
    let schema = infer_schema(&metadata).unwrap();
    let row_groups = metadata.row_groups.clone();
    let projection = None;

    let reader = FileReader::new(file, row_groups, schema.clone(), projection, None, None);
    let (tx, rx) = mpsc::channel::<Result<Bytes, std::io::Error>>(8);

    tokio::spawn(async move {
        let mut first = true;
        let _ = tx.send(Ok(Bytes::from("["))).await;

        for maybe_batch in reader {
            let batch = maybe_batch.unwrap();
            let columns = batch.columns();
            let names = schema.fields.iter().map(|f| f.name.as_str()).collect::<Vec<_>>();

            for row_idx in 0..batch.len() {
                let mut map = Map::new();
                for (col_idx, col) in columns.iter().enumerate() {
                    let name = names
                        .get(col_idx)
                        .map(|s| s.to_string())
                        .unwrap_or_else(|| format!("col_{}", col_idx));
                    let value = match schema.fields[col_idx].data_type {
                        DataType::Utf8 => {
                            let arr = col.as_any().downcast_ref::<Utf8Array<i32>>().unwrap();
                            Value::from(arr.value(row_idx))
                        }
                        DataType::Int32 => {
                            let arr = col.as_any().downcast_ref::<PrimitiveArray<i32>>().unwrap();
                            Value::from(arr.value(row_idx))
                        }
                        _ => Value::Null,
                    };
                    map.insert(name, value);
                }
                let json = Value::Object(map).to_string();
                let line = if first {
                    first = false;
                    json
                } else {
                    format!(",{}", json)
                };
                if tx.send(Ok(Bytes::from(line))).await.is_err() {
                    return;
                }
            }
        }

        let _ = tx.send(Ok(Bytes::from("]"))).await;
        let _ = tokio::fs::remove_file(&temp_path).await;
    });

    let body = StreamBody::new(ReceiverStream::new(rx).map_ok(Frame::data));
    Response::builder()
        .header(header::CONTENT_TYPE, "application/json")
        .body(body)
        .unwrap()
}
