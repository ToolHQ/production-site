#[derive(Debug, PartialEq, Eq)]
pub enum HttpVersion {
  Http09,
  Http10,
  Http11,
}

impl HttpVersion {
  pub fn parse(input: &str) -> Option<Self> {
    match input {
      "HTTP/1.0" => Some(HttpVersion::Http10),
      "HTTP/1.1" => Some(HttpVersion::Http11),
      _ => None,
    }
  }

  pub fn default_keep_alive(&self) -> bool {
    match self {
      HttpVersion::Http09 => false,
      HttpVersion::Http10 => false,
      HttpVersion::Http11 => true,
    }
  }

  //   pub fn requires_host(&self) -> bool {
  //     matches!(self, HttpVersion::Http11)
  //   }
}
