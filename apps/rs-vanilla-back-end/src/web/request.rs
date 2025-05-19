use crate::web::protocol::HttpStatusCode;
use crate::web::protocol::HttpVersion;
use std::collections::HashMap;
use std::io::Write;
use std::net::TcpStream;

pub struct HttpRequest {
  pub method: String,
  pub path: String,
  pub version: HttpVersion,
  pub headers: HashMap<String, String>,
  pub bytes_read: usize,
  pub peer_addr: std::net::SocketAddr,
}

pub struct HttpResponse {
  pub status_code: HttpStatusCode,
  version: HttpVersion,
  pub headers_sent: bool,
  headers: HashMap<String, String>,
  stream: TcpStream,
}

impl HttpResponse {
  pub fn new(version: HttpVersion, stream: TcpStream) -> Self {
    HttpResponse {
      status_code: HttpStatusCode::Ok,
      version,
      headers_sent: false,
      headers: HashMap::new(),
      stream,
    }
  }

  pub fn send_headers(&mut self) {
    if self.headers_sent {
      return;
    }
    self
      .stream
      .write_all(
        format!(
          "{} {} {}\r\n",
          self.version.get_default(),
          self.status_code as u16,
          self.status_code.to_string()
        )
        .as_bytes(),
      )
      .unwrap();
    for (key, value) in &self.headers {
      self
        .stream
        .write_all(format!("{}: {}\r\n", key, value).as_bytes())
        .unwrap();
    }
    self.stream.write_all(b"\r\n").unwrap();
    self.headers_sent = true;
  }

  pub fn set_status_code(&mut self, status_code: HttpStatusCode) {
    self.status_code = status_code;
  }

  pub fn set_header(&mut self, key: &str, value: &str) {
    self.headers.insert(key.to_string(), value.to_string());
  }

  pub fn write_all(&mut self, data: &[u8]) {
    if !self.headers_sent {
      self.send_headers();
    }
    self.stream.write_all(data).unwrap();
  }

  pub fn flush(&mut self) {
    if !self.headers_sent {
      self.send_headers();
    }
    self.stream.flush().unwrap();
  }
}

impl HttpRequest {
  pub fn should_keep_alive(&self) -> bool {
    if let Some(conn) = self.headers.get("connection") {
      return conn.eq_ignore_ascii_case("keep-alive");
    }
    self.version.default_keep_alive()
  }

  //   pub fn is_valid(&self) -> bool {
  //     if self.version.requires_host() {
  //       self.headers.contains_key("host")
  //     } else {
  //       true
  //     }
  //   }

  pub fn is_strict_match(&self, method: &str, path: &str) -> bool {
    self.method.eq_ignore_ascii_case(method) && self.path == path
  }
}
