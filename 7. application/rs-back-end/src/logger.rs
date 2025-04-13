use chrono::Utc;
use indexmap::IndexMap;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::env;

#[derive(Clone)]
pub struct JsonLogger {
    environment: String,
}

impl JsonLogger {
    pub fn new() -> Self {
        let environment = env::var("RUST_ENV").unwrap_or_else(|_| "dev".into());
        Self { environment }
    }

    pub fn info(&self, message: &str, extra: Option<Value>) {
        self.log("info", message, extra);
    }

    pub fn warn(&self, message: &str, extra: Option<Value>) {
        self.log("warn", message, extra);
    }

    pub fn error(&self, message: &str, extra: Option<Value>) {
        self.log("error", message, extra);
    }

    fn log(&self, level: &str, message: &str, extra: Option<Value>) {
        let mut log_obj = IndexMap::new();
        log_obj.insert("severity", json!(level));
        // log_obj.insert(
        //     "app@timestamp",
        //     json!(Utc::now().to_rfc3339())
        // );
        log_obj.insert(
            "app@timestamp",
            json!(Utc::now().format("%Y-%m-%dT%H:%M:%S%.3f").to_string()),
        );
        log_obj.insert(
            "file",
            json!(format!(
                "{}/{}:{}:{}",
                env!("CARGO_MANIFEST_DIR"),
                file!(),
                line!(),
                column!()
            )),
        );
        log_obj.insert("environment", json!(self.environment.clone()));
        log_obj.insert("message", json!(message));
        if let Some(ref val) = extra {
            if let Some(obj) = val.as_object() {
                for (k, v) in obj {
                    log_obj.insert(k, v.clone());
                }
            }
        }

        println!("{}", serde_json::to_string(&log_obj).unwrap());
    }
}
