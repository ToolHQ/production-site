use crate::HttpVersion;
use std::collections::HashMap;

pub struct HttpRequest {
  pub method: String,
  pub path: String,
  pub version: HttpVersion,
  pub headers: HashMap<String, String>,
  pub bytes_read: usize,
  pub peer_addr: std::net::SocketAddr,
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
