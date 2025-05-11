use chrono::Utc;
// use std::time::SystemTime;

pub fn get_current_time_utc_string() -> String {
  Utc::now().format("%Y-%m-%dT%H:%M:%S%.3f").to_string()
}
