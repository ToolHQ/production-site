mod logger;
mod semaphore;
mod time;
mod web;
use semaphore::Semaphore;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::Arc;
use std::thread;
use time::get_current_time_utc_string;
use web::{protocol::HttpVersion, request::HttpRequest, utils::read_http_request};
const MAX_CONCURRENT_CONNECTIONS: usize = 100;
const SERVER_PORT: u16 = 3000;

fn main() {
  let time = get_current_time_utc_string();
  let semaphore = Arc::new(Semaphore::new(MAX_CONCURRENT_CONNECTIONS));
  let listener = TcpListener::bind(format!("0.0.0.0:{}", SERVER_PORT)).expect("Failed to bind");

  let bytes_alloc_per_request = std::mem::size_of::<HttpRequest>();
  log_info!(
    "Teste with extra data",
    &json_map! {
      a: 'a'
    }
  );
  log_info!("Teste with extra data more compact", {
    a: 'a'
  });
  log_info!("Teste without extra data");
  // log_action_info!("Test action", "Test action message");
  log_action_info!("Server Start", format!("🟢 Starting server at {}", time).as_str(), {
    server_start_time: time,
    server_port: SERVER_PORT,
    bytes_alloc_per_request: bytes_alloc_per_request,
    max_concurrency_connections: MAX_CONCURRENT_CONNECTIONS,
  });

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
    thread::spawn(move || {
      sem.acquire();
      handle_client(stream);
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

fn handle_client(mut stream: TcpStream) {
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
    let Some(http_request) = read_http_request(&mut stream, &mut buf_reader, peer_addr) else {
      return;
    };

    // Handles GET /health
    if http_request.is_strict_match("GET", "/health") {
      let _ = stream.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n");
      if !http_request.should_keep_alive() {
        close_connection(stream);
        break;
      }
      continue;
    }

    // Handles GET /ndjson
    if http_request.is_strict_match("GET", "/ndjson") {
      if let Ok(file) = File::open("/app/data/flights-1m.ndjson") {
        let _ = stream.write_all(
                    b"HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nContent-Disposition: attachment; filename=\"file.ndjson\"\r\n\r\n",
                );

        {
          let mut reader = BufReader::with_capacity(1024 * 10, file);
          let mut line = String::new();
          while reader.read_line(&mut line).unwrap_or(0) > 0 {
            let _ = stream.write_all(line.as_bytes());
            let _ = stream.flush();
            line.clear();
          }
        }
        // Logs request
        log_action_info!(
          "Request Received",
          format!("{} {}", http_request.method, http_request.path).as_str(),
          {
            http_method: http_request.method,
            http_path: http_request.path,
            http_peer_addr: http_request.peer_addr,
            bytes_read: http_request.bytes_read,
            http_header_connection: http_request.headers.get("connection").unwrap_or(&"".to_string()),
          }
        );
        close_connection(stream);
        return;
      } else {
        let _ = stream.write_all(b"HTTP/1.1 500 Internal Server Error\r\n\r\nFile not found");
        close_connection(stream);
        return;
      }
    }

    let connection_header = http_request
      .headers
      .get("connection")
      .unwrap_or(&"close".to_string())
      .to_string();

    // Send 404 as default
    let response_body = format!(
      "You requested {} {}\nFrom {} (bytes read: {})\n",
      http_request.method, http_request.path, http_request.peer_addr, http_request.bytes_read
    );
    let response = format!(
            "HTTP/1.1 404 Not Found\r\nContent-Length: {}\r\nConnection: {}\r\nContent-Type: text/plain\r\n\r\n{}",
            response_body.len(),
            connection_header,
            response_body
        );
    let _ = stream.write_all(response.as_bytes());

    // Logs request
    log_action_error!(
      "Request Received",
      format!("{} {}", http_request.method, http_request.path).as_str(),
      &json_map! {
        http_method: http_request.method,
        http_path: http_request.path,
        http_peer_addr: http_request.peer_addr,
        bytes_read: http_request.bytes_read,
        http_header_connection: connection_header,
        response_body: response_body,
      }
    );

    if !http_request.should_keep_alive() {
      // If the connection header is "close", close the connection
      close_connection(stream);
      break;
    }
  }
}
