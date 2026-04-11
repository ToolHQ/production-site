use axum::{
  body::Body,
  http::{header, StatusCode},
  response::{IntoResponse, Response},
  routing::get,
  Router,
};
use serde_json::json;
use std::{fs, path::PathBuf, process::Command};
use tokio_util::io::ReaderStream;

use crate::logger::JsonLogger;

/// GET /heaptrack-report
/// Streams the latest heaptrack report as .gz file
async fn get_heaptrack_report() -> Result<Response, StatusCode> {
  let latest = find_latest_heaptrack_file().ok_or(StatusCode::NOT_FOUND)?;
  let file = tokio::fs::File::open(&latest)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
  let stream = ReaderStream::new(file);

  let file_name = latest
    .file_name()
    .map(|n| n.to_string_lossy().into_owned())
    .unwrap_or_else(|| "heaptrack.gz".to_string());

  Response::builder()
    .status(StatusCode::OK)
    .header(header::CONTENT_TYPE, "application/gzip")
    .header(
      header::CONTENT_DISPOSITION,
      format!("attachment; filename=\"{}\"", file_name),
    )
    .body(Body::from_stream(stream))
    .map_err(|e| {
      JsonLogger::new().error(&format!("Error building heaptrack response: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })
}

/// GET /heaptrack-stats
/// Runs heaptrack_print -f <file> and returns JSON-wrapped summary (as text lines)
async fn get_heaptrack_stats() -> Result<impl IntoResponse, StatusCode> {
  let latest = find_latest_heaptrack_file().ok_or(StatusCode::NOT_FOUND)?;

  let output = Command::new("heaptrack_print")
    .arg("-f")
    .arg(&latest)
    .output()
    .map_err(|e| {
      JsonLogger::new().error(&format!("heaptrack_print execution error: {:?}", e), None);
      StatusCode::INTERNAL_SERVER_ERROR
    })?;

  if !output.status.success() {
    JsonLogger::new().error(
      &format!(
        "heaptrack_print failed with status: {:?}\nstderr: {}",
        output.status,
        String::from_utf8_lossy(&output.stderr)
      ),
      None,
    );
    return Err(StatusCode::INTERNAL_SERVER_ERROR);
  }

  let stdout = String::from_utf8_lossy(&output.stdout);
  let lines: Vec<String> = stdout.lines().map(|s| s.trim().to_string()).collect();

  let file_name = latest
    .file_name()
    .map(|n| n.to_string_lossy().into_owned())
    .unwrap_or_else(|| "heaptrack.gz".to_string());

  Ok(axum::Json(json!({
    "file": file_name,
    "summary": lines,
  })))
}

/// Helper: Finds the most recent heaptrack-*.gz file in /
fn find_latest_heaptrack_file() -> Option<PathBuf> {
  fs::read_dir("/")
    .ok()?
    .filter_map(|e| e.ok())
    .map(|e| e.path())
    .filter_map(|p| {
      let filename = p.file_name()?.to_string_lossy();
      let ext = p.extension()?.to_string_lossy();
      if filename.starts_with("heaptrack") && ext == "gz" {
        Some(p)
      } else {
        None
      }
    })
    .max()
}

/// Router you can `.merge()` into your app
pub fn heaptrack_router() -> Router {
  Router::new()
    .route("/heaptrack-report", get(get_heaptrack_report))
    .route("/heaptrack-stats", get(get_heaptrack_stats))
}
