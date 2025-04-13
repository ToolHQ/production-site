use std::sync::{Arc, Mutex};
use std::collections::HashMap;

use serde_json::{json, Value};
use sqlx::{Row, Column};

use crate::config::{DbConfig};
use crate::state::get_or_init_pool;

type Listener = Arc<Mutex<dyn Fn(String, Option<Value>) + Send + Sync>>;
type QueryHandler = Arc<Mutex<dyn Fn(&str) -> String + Send + Sync>>;
use once_cell::sync::Lazy;

static LISTENER: Lazy<Mutex<Option<Listener>>> = Lazy::new(|| Mutex::new(None));
static WRAP_QUERY_HANDLER: Lazy<Mutex<Option<QueryHandler>>> = Lazy::new(|| Mutex::new(None));

pub mod config;
pub mod state;
pub mod stream;

pub fn set_listener(f: impl Fn(String, Option<Value>) + Send + Sync + 'static) {
    LISTENER.lock().unwrap().replace(Arc::new(Mutex::new(f)));
}

pub fn set_wrap_query_handler(f: impl Fn(&str) -> String + Send + Sync + 'static) {
    WRAP_QUERY_HANDLER.lock().unwrap().replace(Arc::new(Mutex::new(f)));
}

pub async fn query(
    sql: &str,
) -> anyhow::Result<Vec<HashMap<String, Value>>> {
    let config = DbConfig::from_env().ok_or_else(|| anyhow::anyhow!("Missing DB config"))?;
    let pool = get_or_init_pool(&config).await?;

    let wrapped_sql = WRAP_QUERY_HANDLER
        .lock()
        .unwrap()
        .as_ref()
        .map(|f| f.lock().unwrap()(sql))
        .unwrap_or_else(|| sql.to_string());

    let rows = sqlx::query(&wrapped_sql).fetch_all(&*pool).await?;

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

    if let Some(listener) = LISTENER.lock().unwrap().as_ref() {
        listener.lock().unwrap()("query:done".to_string(), Some(json!({ "sql": wrapped_sql })));
    }

    Ok(result)
}
