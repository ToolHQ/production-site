use chrono::Utc;
use serde_json::{Map, Value};

pub struct Logger;

impl Logger {
  pub fn new() -> Self {
    Logger
  }

  #[track_caller]
  pub fn info(&self, message: &str) {
    self.log("info", message, None);
  }

  #[track_caller]
  fn log(&self, severity: &str, message: &str, extra: Option<&Map<String, Value>>) {
    let location = std::panic::Location::caller();
    let now = Utc::now();
    let mut log_obj = Map::with_capacity(6 + extra.map_or(0, |e| e.len()));

    log_obj.insert("severity".into(), Value::String(severity.into()));
    log_obj.insert(
      "app@timestamp".into(),
      Value::String(format!("{}", now.format("%Y-%m-%dT%H:%M:%S%.3f"))),
    );
    log_obj.insert(
      "file".into(),
      Value::String(format!("{}:{}", location.file(), location.line())),
    );
    // log_obj.insert("environment".into(), Value::String(self.environment.clone()));
    log_obj.insert("message".into(), Value::String(message.into()));

    if let Some(obj) = extra {
      log_obj.extend(obj.iter().map(|(k, v)| (k.clone(), v.clone())));
    }

    println!("{}", serde_json::to_string(&log_obj).unwrap());
  }
}
