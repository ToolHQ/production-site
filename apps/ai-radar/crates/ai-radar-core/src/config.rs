//! Application configuration loaded from environment variables.
//!
//! Uses `figment` to assemble configuration from process environment, falling
//! back to documented defaults for non-secret options. Secrets (database URL,
//! LLM API key, GitHub token) are intentionally `Option<String>` so that the
//! deterministic-only mode (`LLM_ENABLED=false`, no DB usage in T-159) keeps
//! working when only a subset of variables is supplied.
//!
//! All variable names are documented in `apps/ai-radar/.env.example`.

use figment::providers::Env;
use figment::Figment;
use serde::Deserialize;

/// Configuration error surfaced to the caller.
///
/// `figment::Error` is boxed because it is large (>200 bytes) and would
/// otherwise inflate every `Result<_, ConfigError>` on the call sites.
#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    /// Environment parsing or extraction failed.
    #[error("failed to load configuration from environment: {0}")]
    Load(#[from] Box<figment::Error>),
}

/// Default bind address for the HTTP server.
pub const DEFAULT_API_BIND: &str = "0.0.0.0:8080";
/// Default log level when neither `AI_RADAR_LOG_LEVEL` nor `RUST_LOG` is set.
pub const DEFAULT_LOG_LEVEL: &str = "info";
/// Default `OpenRouter` base URL (OpenAI-compatible).
pub const DEFAULT_LLM_BASE_URL: &str = "https://openrouter.ai/api/v1";
/// Default LLM request timeout in seconds.
pub const DEFAULT_LLM_TIMEOUT_SECONDS: u64 = 60;

/// Strongly-typed application configuration.
///
/// Populated via [`AppConfig::from_env`] which reads variables prefixed with
/// `AI_RADAR_` plus a small allowlist of bare names (`DATABASE_URL`,
/// `LLM_*`, `GITHUB_TOKEN`).
#[derive(Debug, Clone, Deserialize)]
pub struct AppConfig {
    /// Bind address for the HTTP API. Env: `AI_RADAR_API_BIND`.
    #[serde(default = "default_api_bind")]
    pub api_bind: String,

    /// Tracing log level. Env: `AI_RADAR_LOG_LEVEL` (also honors `RUST_LOG`).
    #[serde(default = "default_log_level")]
    pub log_level: String,

    /// Postgres connection string. Env: `DATABASE_URL`.
    /// Optional in T-159 because the workspace bootstrap does not require a
    /// database. Becomes mandatory once T-160 lands.
    pub database_url: Option<String>,

    /// Toggle the LLM provider. Env: `LLM_ENABLED`. Default `false` to keep
    /// the deterministic-only path operational without secrets.
    #[serde(default)]
    pub llm_enabled: bool,

    /// LLM endpoint (OpenAI-compatible). Env: `LLM_BASE_URL`.
    #[serde(default = "default_llm_base_url")]
    pub llm_base_url: String,

    /// LLM API key. Env: `LLM_API_KEY`.
    pub llm_api_key: Option<String>,

    /// LLM model identifier. Env: `LLM_MODEL`.
    pub llm_model: Option<String>,

    /// LLM HTTP timeout in seconds. Env: `LLM_TIMEOUT_SECONDS`.
    #[serde(default = "default_llm_timeout_seconds")]
    pub llm_timeout_seconds: u64,

    /// GitHub token for higher rate limit. Env: `GITHUB_TOKEN`.
    pub github_token: Option<String>,
}

fn default_api_bind() -> String {
    DEFAULT_API_BIND.to_string()
}
fn default_log_level() -> String {
    DEFAULT_LOG_LEVEL.to_string()
}
fn default_llm_base_url() -> String {
    DEFAULT_LLM_BASE_URL.to_string()
}
fn default_llm_timeout_seconds() -> u64 {
    DEFAULT_LLM_TIMEOUT_SECONDS
}

impl AppConfig {
    /// Build configuration from process environment.
    ///
    /// # Errors
    ///
    /// Returns [`ConfigError::Load`] when figment cannot parse a typed value
    /// (e.g. `LLM_TIMEOUT_SECONDS` not a valid `u64`).
    pub fn from_env() -> Result<Self, ConfigError> {
        let figment = Figment::new()
            .merge(Env::prefixed("AI_RADAR_"))
            .merge(Env::raw().only(&[
                "DATABASE_URL",
                "LLM_ENABLED",
                "LLM_BASE_URL",
                "LLM_API_KEY",
                "LLM_MODEL",
                "LLM_TIMEOUT_SECONDS",
                "GITHUB_TOKEN",
            ]));

        figment
            .extract()
            .map_err(|e| ConfigError::Load(Box::new(e)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use figment::Jail;

    #[test]
    fn loads_defaults_when_env_is_empty() {
        Jail::expect_with(|jail| {
            jail.clear_env();
            let cfg = AppConfig::from_env().expect("defaults must load");
            assert_eq!(cfg.api_bind, DEFAULT_API_BIND);
            assert_eq!(cfg.log_level, DEFAULT_LOG_LEVEL);
            assert_eq!(cfg.llm_base_url, DEFAULT_LLM_BASE_URL);
            assert_eq!(cfg.llm_timeout_seconds, DEFAULT_LLM_TIMEOUT_SECONDS);
            assert!(!cfg.llm_enabled);
            assert!(cfg.database_url.is_none());
            assert!(cfg.llm_api_key.is_none());
            assert!(cfg.github_token.is_none());
            Ok(())
        });
    }

    #[test]
    fn honors_ai_radar_prefixed_overrides() {
        Jail::expect_with(|jail| {
            jail.clear_env();
            jail.set_env("AI_RADAR_API_BIND", "127.0.0.1:9090");
            jail.set_env("AI_RADAR_LOG_LEVEL", "debug");
            let cfg = AppConfig::from_env().expect("must load");
            assert_eq!(cfg.api_bind, "127.0.0.1:9090");
            assert_eq!(cfg.log_level, "debug");
            Ok(())
        });
    }

    #[test]
    fn parses_secrets_and_typed_fields() {
        Jail::expect_with(|jail| {
            jail.clear_env();
            jail.set_env("DATABASE_URL", "postgres://u:p@h/db");
            jail.set_env("LLM_ENABLED", "true");
            jail.set_env("LLM_API_KEY", "sk-test");
            jail.set_env("LLM_MODEL", "openrouter/auto");
            jail.set_env("LLM_TIMEOUT_SECONDS", "30");
            jail.set_env("GITHUB_TOKEN", "ghp_test");
            let cfg = AppConfig::from_env().expect("must load");
            assert_eq!(cfg.database_url.as_deref(), Some("postgres://u:p@h/db"));
            assert!(cfg.llm_enabled);
            assert_eq!(cfg.llm_api_key.as_deref(), Some("sk-test"));
            assert_eq!(cfg.llm_model.as_deref(), Some("openrouter/auto"));
            assert_eq!(cfg.llm_timeout_seconds, 30);
            assert_eq!(cfg.github_token.as_deref(), Some("ghp_test"));
            Ok(())
        });
    }

    #[test]
    fn invalid_typed_field_surfaces_load_error() {
        Jail::expect_with(|jail| {
            jail.clear_env();
            jail.set_env("LLM_TIMEOUT_SECONDS", "not-a-number");
            let err = AppConfig::from_env().expect_err("should fail to parse");
            matches!(err, ConfigError::Load(_));
            Ok(())
        });
    }
}
