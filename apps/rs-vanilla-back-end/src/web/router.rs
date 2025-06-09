use crate::web::protocol::{HttpMethod, HttpStatusCode};
use crate::web::request::{HttpRequest, HttpResponse};
use std::collections::HashMap;

type HandlerFn = fn(&HttpRequest, &mut HttpResponse) -> Option<()>;

type RouteKey = (HttpMethod, &'static str);

#[derive(Clone)]
pub struct Router {
  routes: HashMap<RouteKey, HandlerFn>,
}

impl Router {
  pub fn new() -> Self {
    Self {
      routes: HashMap::new(),
    }
  }

  pub fn get(mut self, path: &'static str, handler: HandlerFn) -> Self {
    self.routes.insert((HttpMethod::Get, path), handler);
    self
  }

  #[allow(dead_code)]
  pub fn post(mut self, path: &'static str, handler: HandlerFn) -> Self {
    self.routes.insert((HttpMethod::Post, path), handler);
    self
  }

  pub fn route(&self, req: &HttpRequest, res: &mut HttpResponse) -> Option<()> {
    let method_str = &req.method;
    let method = HttpMethod::from_str(method_str);
    let path = req.path.as_str();
    match self.routes.get(&(method, path)) {
      Some(handler) => handler(req, res),
      None => {
        res.set_status_code(HttpStatusCode::NotFound);
        res.send_headers();
        res.should_force_close_connection = true;
        None
      }
    }
  }
}
