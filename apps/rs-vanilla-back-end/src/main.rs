mod logger;
mod semaphore;
mod time;
mod web;
use logger::{clear_request_context, set_request_context};
use semaphore::Semaphore;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::net::{TcpListener, TcpStream};
use std::sync::Arc;
use std::thread;
use time::get_current_time_utc_string;
use uuid::Uuid;
use web::protocol::HttpStatusCode;
use web::{
  protocol::HttpVersion, request::HttpRequest, request::HttpResponse, router::Router,
  utils::read_http_request,
};
const MAX_CONCURRENT_CONNECTIONS: usize = 100;
const SERVER_PORT: u16 = 3000;

fn handle_http_health_check(_: &HttpRequest, http_response: &mut HttpResponse) -> Option<()> {
  http_response.set_status_code(HttpStatusCode::Ok);
  http_response.set_header("Content-Length", "0");
  return None;
}

fn handle_ndjson_request(_: &HttpRequest, http_response: &mut HttpResponse) -> Option<()> {
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

fn main() {
  let time = get_current_time_utc_string();
  let semaphore = Arc::new(Semaphore::new(MAX_CONCURRENT_CONNECTIONS));
  let listener = TcpListener::bind(format!("0.0.0.0:{}", SERVER_PORT)).expect("Failed to bind");
  let bytes_alloc_per_request = std::mem::size_of::<HttpRequest>();

  log_action_info!("Server Start", format!("🟢 Starting server at {}", time).as_str(), {
    server_start_time: time,
    server_port: SERVER_PORT,
    bytes_alloc_per_request: bytes_alloc_per_request,
    max_concurrency_connections: MAX_CONCURRENT_CONNECTIONS,
  });

  let router = Router::new()
    .get("/health", handle_http_health_check)
    .get("/ndjson", handle_ndjson_request);

  for stream in listener.incoming() {
    let stream = match stream {
      Ok(s) => s,
      Err(e) => {
        log_action_error!(
          "Connection failed",
          format!("❌ Connection failed: {}", e),
          {
              error: e.to_string(),
          }
        );
        continue;
      }
    };

    let sem = semaphore.clone();
    let cloned_router = router.clone();
    thread::spawn(move || {
      sem.acquire();
      handle_client(stream, &cloned_router);
      sem.release();
    });
  }
}

fn close_connection(stream: TcpStream) {
  if let Err(e) = stream.shutdown(std::net::Shutdown::Both) {
    log_error!(
      format!("Failed to close connection: {}", e).as_str(),
      &json_map! {
          error: e.to_string(),
      }
    );
  }
}

fn handle_client(mut stream: TcpStream, router: &Router) {
  let peer_addr = match stream.peer_addr() {
    Ok(addr) => addr,
    Err(_) => return,
  };

  let mut buf_reader = match stream.try_clone() {
    Ok(s) => BufReader::new(s),
    Err(e) => {
      log_error!(
        format!("Failed to clone stream: {}", e).as_str(),
        &json_map! {
            error: e.to_string(),
        }
      );
      close_connection(stream);
      return;
    }
  };

  // Loop to support request pipelining
  loop {
    // Inits req-id
    let req_id = Uuid::new_v4().to_string();
    // Measure response time
    let start_time = std::time::Instant::now();
    set_request_context("req-id", req_id.as_str());

    let Some(http_request) = read_http_request(&mut stream, &mut buf_reader, peer_addr) else {
      return;
    };

    let mut http_response = HttpResponse::new(http_request.version, stream.try_clone().unwrap());

    router.route(&http_request, &mut http_response);

    if !http_response.headers_sent {
      http_response.send_headers();
    }
    let ok = http_response.status_code as u16 == 200;
    let elapsed_time = start_time.elapsed();
    let elapsed_time_ms = elapsed_time.as_millis();
    let elapsed_time_str = format!("{}ms", elapsed_time_ms);
    // Logs request
    if ok {
      if http_request.path != "/health" {
        log_action_info!(
          "Request Received",
          format!("{} {}", http_request.method, http_request.path).as_str(),
          {
            http_method: http_request.method,
            http_path: http_request.path,
            http_peer_addr: http_request.peer_addr,
            bytes_read: http_request.bytes_read,
            http_status_code: http_response.status_code as u16,
            elapsed_time: elapsed_time_str.as_str(),
          }
        );
      }
    } else {
      log_action_error!(
        "Request Received",
        format!("{} {}", http_request.method, http_request.path).as_str(),
        {
          http_method: http_request.method,
          http_path: http_request.path,
          http_peer_addr: http_request.peer_addr,
          bytes_read: http_request.bytes_read,
          http_status_code: http_response.status_code as u16,
          elapsed_time: elapsed_time_str.as_str(),
        }
      );
    }

    clear_request_context();
    if !http_request.should_keep_alive() || http_response.should_force_close_connection {
      close_connection(stream);
      break;
    }
  }
}
