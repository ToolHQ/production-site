use std::sync::{Arc, Mutex};
use std::collections::HashMap;

use serde_json::{json, Value};
use sqlx::{Row, Column};

use crate::config::{DbConfig};
use crate::state::get_or_init_pool;
use crate::context::try_with_context;
use crate::logger::JsonLogger;
use std::time::Instant;

type Listener = Arc<Mutex<dyn Fn(String, Option<Value>) + Send + Sync>>;
type QueryHandler = Arc<Mutex<dyn Fn(&str) -> String + Send + Sync>>;
use once_cell::sync::Lazy;

static LISTENER: Lazy<Mutex<Option<Listener>>> = Lazy::new(|| Mutex::new(None));
static WRAP_QUERY_HANDLER: Lazy<Mutex<Option<QueryHandler>>> = Lazy::new(|| Mutex::new(None));

pub mod config;
pub mod state;
pub mod stream;
pub mod context;
pub mod logger;

pub fn set_listener(f: impl Fn(String, Option<Value>) + Send + Sync + 'static) {
    if let Ok(mut guard) = LISTENER.lock() {
        guard.replace(Arc::new(Mutex::new(f)));
    }
}

pub fn set_wrap_query_handler(f: impl Fn(&str) -> String + Send + Sync + 'static) {
    if let Ok(mut guard) = WRAP_QUERY_HANDLER.lock() {
        guard.replace(Arc::new(Mutex::new(f)));
    }
}

pub async fn query(
    sql: &str,
    bindings: Option<Value>, // Optional: you can pass values here for logging
) -> anyhow::Result<Vec<HashMap<String, Value>>> {

    let config = DbConfig::from_env().ok_or_else(|| anyhow::anyhow!("Missing DB config"))?;
    let pool = get_or_init_pool(&config).await?;

    let wrapped_sql = WRAP_QUERY_HANDLER
        .lock()
        .ok()
        .and_then(|guard| {
            guard.as_ref().and_then(|f| {
                f.lock().ok().map(|handler| handler(sql))
            })
        })
        .unwrap_or_else(|| sql.to_string());

    let start_time = Instant::now();
    let rows = sqlx::query(&wrapped_sql).fetch_all(&*pool).await?;
    let elapsed_ms = start_time.elapsed().as_secs_f64() * 1000.0;

    let mut result = Vec::new();
    for row in rows {
        let mut map = HashMap::new();
        for column in row.columns() {
            let name = column.name().to_string();
            let value: Value = row.try_get(column.name())?;
            map.insert(name, value);
        }
        result.push(map);
    }

    let bindings_clone = bindings.clone();

    let ctx = try_with_context(|ctx| {
        json!({
            "sql": wrapped_sql,
            "bindings": bindings_clone.clone().unwrap_or(json!(null)),
            "elapsedTime": format!("{:.3}ms", elapsed_ms),
            "req-id": ctx.req_id.clone().unwrap_or_default(),
            "session-id": ctx.session_id.clone().unwrap_or_default()
        })
    }).unwrap_or_else(|| {
        json!({
            "sql": wrapped_sql,
            "bindings": bindings.clone().unwrap_or(json!(null)),
            "elapsedTime": format!("{:.3}ms", elapsed_ms),
            "req-id": null,
            "session-id": null
        })
    });

    let location = std::panic::Location::caller();
    let logger = JsonLogger::from_location(location.file(), location.line());
    logger.info("DB QUERY", Some(ctx.clone()));

    if let Ok(guard) = LISTENER.lock() {
        if let Some(listener) = guard.as_ref() {
            if let Ok(f) = listener.lock() {
                f("DB QUERY".to_string(), Some(ctx));
            }
        }
    }

    Ok(result)
}
