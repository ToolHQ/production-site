use std::sync::Arc;

use dashmap::DashMap;
use once_cell::sync::Lazy;
use sqlx::{postgres::PgPoolOptions, PgPool};

use crate::config::{ConnectionType, DbConfig};

static DB_POOLS: Lazy<DashMap<ConnectionType, Arc<PgPool>>> = Lazy::new(DashMap::new);

pub async fn get_or_init_pool(config: &DbConfig) -> anyhow::Result<Arc<PgPool>> {
    if let Some(pool) = DB_POOLS.get(&config.connection_type) {
        return Ok(pool.clone());
    }

    let pool = PgPoolOptions::new()
        .max_connections(10)
        .connect(&config.to_url())
        .await?;

    let arc_pool = Arc::new(pool);
    DB_POOLS.insert(config.connection_type.clone(), arc_pool.clone());
    Ok(arc_pool)
}

pub fn get_existing_pool(connection_type: &ConnectionType) -> Option<Arc<PgPool>> {
    DB_POOLS.get(connection_type).map(|pool| pool.clone())
}

pub fn destroy_pool(connection_type: &ConnectionType) {
    DB_POOLS.remove(connection_type);
}
