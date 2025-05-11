use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;

use crate::HttpRequest;
use crate::HttpVersion;

fn try_close_connection(stream: &mut TcpStream) {
  if let Err(e) = stream.shutdown(std::net::Shutdown::Both) {
    eprintln!("Failed to close connection: {}", e);
  }
}

pub fn read_http_request(
  stream: &mut TcpStream,
  buf_reader: &mut BufReader<TcpStream>,
  peer_addr: std::net::SocketAddr,
) -> Option<HttpRequest> {
  let mut request_line = String::with_capacity(1024);

  // Read just the first line not empty or whitespaces of current buffer to get method, path, and version
  let mut bytes_read = 0;
  loop {
    request_line.clear();
    bytes_read += match buf_reader.read_line(&mut request_line) {
      Ok(n) if n == 0 => {
        // EOF: client closed connection cleanly
        try_close_connection(stream);
        return None;
      }
      Ok(n) => n,
      Err(e) => {
        eprintln!("Failed to read from {}: {}", peer_addr, e);
        try_close_connection(stream);
        return None;
      }
    };

    if !request_line.trim_end().is_empty() {
      break;
    }
  }

  let first_line_parts: Vec<&str> = request_line.split_whitespace().collect();

  if first_line_parts.len() == 2 && first_line_parts[0].eq_ignore_ascii_case("get") {
    return Some(HttpRequest {
      method: first_line_parts[0].to_string(),
      path: first_line_parts[1].to_string(),
      version: HttpVersion::Http09,
      headers: HashMap::new(),
      bytes_read,
      peer_addr,
    });
  }

  if first_line_parts.len() < 3 {
    let _ = stream.write_all(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n");
    eprintln!("Invalid request line: {}", request_line);
    try_close_connection(stream);
    return None;
  }

  let http_version = match HttpVersion::parse(first_line_parts[2]) {
    Some(v) => v,
    None => {
      let _ =
        stream.write_all(b"HTTP/1.1 505 HTTP Version Not Supported\r\nContent-Length: 0\r\n\r\n");
      eprintln!("Unsupported HTTP version: {}", first_line_parts[2]);
      try_close_connection(stream);
      return None;
    }
  };

  let mut http_request = HttpRequest {
    method: first_line_parts[0].to_string(),
    path: first_line_parts[1].to_string(),
    version: http_version,
    headers: HashMap::new(),
    bytes_read,
    peer_addr,
  };

  // Read line by line to get the headers using O(1) memory
  loop {
    request_line.clear();
    bytes_read += match buf_reader.read_line(&mut request_line) {
      Ok(n) if n == 0 => {
        try_close_connection(stream);
        return None;
      }
      Ok(n) => n,
      Err(e) => {
        eprintln!("Failed to read from {}: {}", peer_addr, e);
        try_close_connection(stream);
        return None;
      }
    };

    let request_line_trimmed = request_line.trim_end();
    if request_line_trimmed.is_empty() {
      break;
    }

    if let Some((header_name, header_value)) = request_line_trimmed.split_once(':') {
      let header_name = header_name.trim();
      let header_value = header_value.trim();
      http_request.headers.insert(
        header_name.to_lowercase().to_string(),
        header_value.to_string(),
      );
    } else {
      eprintln!("Invalid header: {}", request_line_trimmed);
    }
  }
  return Some(http_request);
}
