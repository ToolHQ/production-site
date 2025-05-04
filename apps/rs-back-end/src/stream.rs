use std::collections::HashMap;

use futures::{Stream, StreamExt};
use serde_json::Value;
use sqlx::{Row, Column};

use crate::config::{DbConfig};
use crate::state::get_or_init_pool;

pub async fn query_stream<'a>(
    sql: &'a str,
) -> anyhow::Result<impl Stream<Item = anyhow::Result<HashMap<String, Value>>> + 'a> {
    let config = DbConfig::from_env().ok_or_else(|| anyhow::anyhow!("Missing DB config"))?;
    let pool = get_or_init_pool(&config).await?;

    let stream = sqlx::query(sql)
        .fetch(&*pool)
        .map(|row_result| {
            let row = row_result?;
            let mut map = HashMap::new();
            for col in row.columns() {
                let name = col.name().to_string();
                let value: Value = row.try_get(col.name())?;
                map.insert(name, value);
            }
            Ok(map)
        });

    Ok(stream)
}
