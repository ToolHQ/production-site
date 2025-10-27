use crate::web::protocol::HttpStatusCode;
use crate::web::{request::HttpRequest, request::HttpResponse};
use std::fs::File;
use std::io::{BufRead, BufReader};

pub fn handle_http_health_check(_: &HttpRequest, http_response: &mut HttpResponse) -> Option<()> {
  http_response.set_status_code(HttpStatusCode::Ok);
  http_response.set_header("Content-Length", "0");
  return None;
}

pub fn handle_ndjson_request(_: &HttpRequest, http_response: &mut HttpResponse) -> Option<()> {
  if let Ok(file) = File::open("/app/data/flights-1m.ndjson") {
    http_response.set_header("Content-Type", "application/x-ndjson");
    http_response.set_header(
      "Content-Disposition",
      "attachment; filename=\"file.ndjson\"",
    );
    {
      let mut reader = BufReader::with_capacity(1024 * 10, file);
      let mut line = String::new();
      while reader.read_line(&mut line).unwrap_or(0) > 0 {
        let _ = http_response.write_all(line.as_bytes());
        let _ = http_response.flush();
        line.clear();
      }
    }
    http_response.should_force_close_connection = true;
    return None;
  } else {
    http_response.set_status_code(HttpStatusCode::NotFound);
    http_response.set_header("Content-Type", "text/plain");
    let _ = http_response.write_all(b"File not found");
    return None;
  }
}
