#[derive(Debug, PartialEq, Eq, Clone, Copy)]
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

  pub fn get_default(&self) -> String {
    match self {
      HttpVersion::Http09 => "HTTP/0.9".to_string(),
      HttpVersion::Http10 => "HTTP/1.0".to_string(),
      HttpVersion::Http11 => "HTTP/1.1".to_string(),
    }
  }
}
#[derive(Clone, Copy)]
pub enum HttpStatusCode {
  Ok = 200,
  #[allow(dead_code)]
  BadRequest = 400,
  NotFound = 404,
  #[allow(dead_code)]
  InternalServerError = 500,
}
impl HttpStatusCode {
  pub fn to_string(&self) -> String {
    match self {
      HttpStatusCode::Ok => "OK".to_string(),
      HttpStatusCode::BadRequest => "Bad Request".to_string(),
      HttpStatusCode::NotFound => "Not Found".to_string(),
      HttpStatusCode::InternalServerError => "Internal Server Error".to_string(),
    }
  }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum HttpMethod {
  Get,
  Post,
  Put,
  Delete,
  Head,
  Options,
  Patch,
  Invalid,
}

impl HttpMethod {
  pub fn from_str(method: &str) -> Self {
    match method {
      "GET" => HttpMethod::Get,
      "POST" => HttpMethod::Post,
      "PUT" => HttpMethod::Put,
      "DELETE" => HttpMethod::Delete,
      "HEAD" => HttpMethod::Head,
      "OPTIONS" => HttpMethod::Options,
      "PATCH" => HttpMethod::Patch,
      _ => HttpMethod::Invalid,
    }
  }
}
