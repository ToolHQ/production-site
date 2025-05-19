use chrono::Utc;
use serde_json::{Map, Value};
use std::collections::HashSet;
use std::panic::Location;
use std::sync::OnceLock;

static ENVIRONMENT: OnceLock<String> = OnceLock::new();
static LOGGER_DEBUG_PATHS: OnceLock<HashSet<String>> = OnceLock::new();

fn get_environment() -> &'static str {
  ENVIRONMENT.get_or_init(|| std::env::var("RUNTIME_ENV").unwrap_or_else(|_| "dev".to_string()))
}

fn get_logger_debug_paths() -> &'static HashSet<String> {
  LOGGER_DEBUG_PATHS.get_or_init(|| {
    std::env::var("LOGGER_DEBUG_PATHS")
      .unwrap_or_default()
      .split(',')
      .filter(|s| !s.trim().is_empty())
      .map(|s| s.trim().to_string())
      .collect()
  })
}

#[derive(PartialEq)]
pub enum Severity {
  Info,
  Error,
  Warn,
  Debug,
}

pub struct Logger;

impl Logger {
  pub fn new() -> Self {
    Logger
  }

  #[track_caller]
  pub fn info(&self, message: impl AsRef<str>, extra: Option<&Map<String, Value>>) {
    self.log(Severity::Info, message.as_ref(), extra);
  }

  #[track_caller]
  pub fn error(&self, message: impl AsRef<str>, extra: Option<&Map<String, Value>>) {
    self.log(Severity::Error, message.as_ref(), extra);
  }

  #[track_caller]
  #[allow(dead_code)]
  pub fn warn(&self, message: impl AsRef<str>, extra: Option<&Map<String, Value>>) {
    self.log(Severity::Warn, message.as_ref(), extra);
  }

  #[track_caller]
  #[allow(dead_code)]
  pub fn debug(&self, message: impl AsRef<str>, extra: Option<&Map<String, Value>>) {
    let location = Location::caller();
    let file_path = location.file();
    // Fast O(1) match against allowed debug paths
    if !get_logger_debug_paths()
      .iter()
      .any(|prefix| file_path.starts_with(prefix))
    {
      return;
    }
    self.log(Severity::Debug, message.as_ref(), extra);
  }

  #[track_caller]
  fn log(&self, severity: Severity, message: &str, extra: Option<&Map<String, Value>>) {
    let severity_str = match severity {
      Severity::Info => "info",
      Severity::Error => "error",
      Severity::Warn => "warn",
      Severity::Debug => "debug",
    };

    let location = Location::caller();
    let now = Utc::now();
    let mut log_obj = Map::with_capacity(6 + extra.map_or(0, |e| e.len()));

    log_obj.insert("environment".into(), get_environment().into());
    log_obj.insert(
      "app@timestamp".into(),
      now.format("%Y-%m-%dT%H:%M:%S%.3f").to_string().into(),
    );
    log_obj.insert("severity".into(), severity_str.into());
    log_obj.insert(
      "file".into(),
      format!("{}:{}", location.file(), location.line()).into(),
    );
    log_obj.insert("message".into(), message.into());

    if let Some(obj) = extra {
      log_obj.extend(obj.clone());
    }

    match severity {
      Severity::Error => eprintln!("{}", serde_json::to_string(&log_obj).unwrap()),
      _ => println!("{}", serde_json::to_string(&log_obj).unwrap()),
    }
  }
}

// === Global logger ===

static LOGGER: OnceLock<Logger> = OnceLock::new();

pub fn get_logger() -> &'static Logger {
  LOGGER.get_or_init(Logger::new)
}

// === Macros ===

#[macro_export]
macro_rules! __key_to_string {
  ($key:ident) => {
    stringify!($key).to_string()
  };
  ($key:literal) => {
    $key.to_string()
  };
}

#[macro_export]
macro_rules! json_map {
  ( $( $key:tt : $val:expr ),* $(,)? ) => {{
    let mut _map = ::serde_json::Map::new();
    $(
      _map.insert($crate::__key_to_string!($key), ::serde_json::json!($val));
    )*
    _map
  }};
}

#[macro_export]
macro_rules! log_info {
  ($msg:expr, { $( $key:tt : $val:expr ),* $(,)? }) => {{
    let mut _map = ::serde_json::Map::new();
    $( _map.insert($crate::__key_to_string!($key), ::serde_json::json!($val)); )*
    $crate::logger::get_logger().info($msg, Some(&_map));
  }};
  ($msg:expr $(, $extra:expr)? ) => {
    crate::logger::get_logger().info($msg, log_info!(@opt $($extra)?))
  };
  (@opt) => { None };
  (@opt $e:expr) => { Some($e) };
}

#[macro_export]
macro_rules! log_action_info {
  ($action:expr, $msg:expr, { $( $key:tt : $val:expr ),* $(,)? }) => {{
    let mut _extra = ::serde_json::Map::new();
    _extra.insert("action".into(), ::serde_json::json!($action));
    $(
      _extra.insert($crate::__key_to_string!($key), ::serde_json::json!($val));
    )*
    $crate::logger::get_logger().info($msg, Some(&_extra));
  }};
  ($action:expr, $msg:expr, $extra:expr) => {{
    let mut _map = ::serde_json::Map::new();
    _map.insert("action".into(), ::serde_json::json!($action));
    _map.extend($extra.iter().map(|(k, v)| (k.clone(), v.clone())));
    $crate::logger::get_logger().info($msg, Some(&_map));
  }};
  ($action:expr, $msg:expr) => {{
    let mut _extra = ::serde_json::Map::new();
    _extra.insert("action".into(), ::serde_json::json!($action));
    $crate::logger::get_logger().info($msg, Some(&_extra));
  }};
}

#[macro_export]
macro_rules! log_error {
  ($msg:expr, { $( $key:tt : $val:expr ),* $(,)? }) => {{
    let mut _map = ::serde_json::Map::new();
    $( _map.insert($crate::__key_to_string!($key), ::serde_json::json!($val)); )*
    $crate::logger::get_logger().error($msg, Some(&_map));
  }};
  ($msg:expr $(, $extra:expr)? ) => {
    crate::logger::get_logger().error($msg, log_error!(@opt $($extra)?))
  };
  (@opt) => { None };
  (@opt $e:expr) => { Some($e) };
}

#[macro_export]
macro_rules! log_action_error {
  ($action:expr, $msg:expr, { $( $key:tt : $val:expr ),* $(,)? }) => {{
    let mut _extra = ::serde_json::Map::new();
    _extra.insert("action".into(), ::serde_json::json!($action));
    $(
      _extra.insert($crate::__key_to_string!($key), ::serde_json::json!($val));
    )*
    $crate::logger::get_logger().error($msg, Some(&_extra));
  }};
  ($action:expr, $msg:expr, $extra:expr) => {{
    let mut _map = ::serde_json::Map::new();
    _map.insert("action".into(), ::serde_json::json!($action));
    _map.extend($extra.iter().map(|(k, v)| (k.clone(), v.clone())));
    $crate::logger::get_logger().error($msg, Some(&_map));
  }};
  ($action:expr, $msg:expr) => {{
    let mut _extra = ::serde_json::Map::new();
    _extra.insert("action".into(), ::serde_json::json!($action));
    $crate::logger::get_logger().error($msg, Some(&_extra));
  }};
}

#[macro_export]
macro_rules! log_warn {
  ($msg:expr, { $( $key:tt : $val:expr ),* $(,)? }) => {{
    let mut _map = ::serde_json::Map::new();
    $( _map.insert($crate::__key_to_string!($key), ::serde_json::json!($val)); )*
    $crate::logger::get_logger().warn($msg, Some(&_map));
  }};
  ($msg:expr $(, $extra:expr)? ) => {
    crate::logger::get_logger().warn($msg, log_warn!(@opt $($extra)?))
  };
  (@opt) => { None };
  (@opt $e:expr) => { Some($e) };
}

#[macro_export]
macro_rules! log_action_warn {
  ($action:expr, $msg:expr, { $( $key:tt : $val:expr ),* $(,)? }) => {{
    let mut _extra = ::serde_json::Map::new();
    _extra.insert("action".into(), ::serde_json::json!($action));
    $(
      _extra.insert($crate::__key_to_string!($key), ::serde_json::json!($val));
    )*
    $crate::logger::get_logger().warn($msg, Some(&_extra));
  }};
  ($action:expr, $msg:expr, $extra:expr) => {{
    let mut _map = ::serde_json::Map::new();
    _map.insert("action".into(), ::serde_json::json!($action));
    _map.extend($extra.iter().map(|(k, v)| (k.clone(), v.clone())));
    $crate::logger::get_logger().warn($msg, Some(&_map));
  }};
  ($action:expr, $msg:expr) => {{
    let mut _extra = ::serde_json::Map::new();
    _extra.insert("action".into(), ::serde_json::json!($action));
    $crate::logger::get_logger().warn($msg, Some(&_extra));
  }};
}

#[macro_export]
macro_rules! log_debug {
  ($msg:expr, { $( $key:tt : $val:expr ),* $(,)? }) => {{
    let mut _map = ::serde_json::Map::new();
    $( _map.insert($crate::__key_to_string!($key), ::serde_json::json!($val)); )*
    $crate::logger::get_logger().debug($msg, Some(&_map));
  }};
  ($msg:expr $(, $extra:expr)? ) => {
    crate::logger::get_logger().debug($msg, log_debug!(@opt $($extra)?))
  };
  (@opt) => { None };
  (@opt $e:expr) => { Some($e) };
}

#[macro_export]
macro_rules! log_action_debug {
  ($action:expr, $msg:expr, { $( $key:tt : $val:expr ),* $(,)? }) => {{
    let mut _extra = ::serde_json::Map::new();
    _extra.insert("action".into(), ::serde_json::json!($action));
    $(
      _extra.insert($crate::__key_to_string!($key), ::serde_json::json!($val));
    )*
    $crate::logger::get_logger().debug($msg, Some(&_extra));
  }};
  ($action:expr, $msg:expr, $extra:expr) => {{
    let mut _map = ::serde_json::Map::new();
    _map.insert("action".into(), ::serde_json::json!($action));
    _map.extend($extra.iter().map(|(k, v)| (k.clone(), v.clone())));
    $crate::logger::get_logger().debug($msg, Some(&_map));
  }};
  ($action:expr, $msg:expr) => {{
    let mut _extra = ::serde_json::Map::new();
    _extra.insert("action".into(), ::serde_json::json!($action));
    $crate::logger::get_logger().debug($msg, Some(&_extra));
  }};
}
