use std::env;

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum ConnectionType {
    PostgreSQL,
    Redshift,
}

#[derive(Debug, Clone)]
pub struct DbConfig {
    pub host: String,
    pub port: u16,
    pub database: String,
    pub user: String,
    pub password: String,
    pub connection_type: ConnectionType,
}

impl DbConfig {
    pub fn from_env() -> Option<Self> {
        let host = env::var("DB_HOST").ok()?;
        let port = env::var("DB_PORT").ok()?.parse().ok()?;
        let database = env::var("DB_NAME").ok()?;
        let user = env::var("DB_USER").ok()?;
        let password = env::var("DB_PASSWORD").ok()?;

        let connection_type = match env::var("DB_CONNECTION_TYPE").ok()?.as_str() {
            "postgres" => ConnectionType::PostgreSQL,
            "redshift" => ConnectionType::Redshift,
            other => {
                eprintln!("⚠️ Unknown DB_CONNECTION_TYPE: {}", other);
                return None;
            }
        };

        Some(Self {
            host,
            port,
            database,
            user,
            password,
            connection_type,
        })
    }

    pub fn to_url(&self) -> String {
        format!(
            "postgres://{}:{}@{}:{}/{}",
            self.user, self.password, self.host, self.port, self.database
        )
    }
}
