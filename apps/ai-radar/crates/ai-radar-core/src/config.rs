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
/// Default cap on LLM HTTP calls per minute (OpenRouter `:free` ≈ 16–20 RPM).
pub const DEFAULT_LLM_MAX_RPM: u32 = 15;
/// Default rows per `ai-radar embed` pass (**T-256**).
pub const DEFAULT_EMBED_BATCH_LIMIT: i64 = 50;
/// Hard ceiling for `EMBED_BATCH_LIMIT` (cost guardrail).
pub const MAX_EMBED_BATCH_LIMIT: i64 = 100;
/// Default rows embedded automatically after each extract pass (**T-259**).
pub const DEFAULT_POST_EXTRACT_EMBED_TAIL_LIMIT: i64 = 25;

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

    /// Minimum spacing between LLM HTTP calls (extract/score). Env: `LLM_MAX_RPM`.
    /// Default `15` (under OpenRouter free-tier ~16–20 RPM). Set `0` to disable pacing.
    #[serde(default = "default_llm_max_rpm")]
    pub llm_max_rpm: u32,

    /// GitHub token for higher rate limit. Env: `GITHUB_TOKEN`.
    pub github_token: Option<String>,

    /// Max concurrent source fetches in `ai-radar collect`. Env:
    /// `AI_RADAR_COLLECT_CONCURRENCY`. Default `2` for the small cluster.
    #[serde(default = "default_collect_concurrency")]
    pub collect_concurrency: usize,

    /// Cap RSS/Atom items ingested per source per run. Env:
    /// `AI_RADAR_MAX_ITEMS_PER_RUN`. Default `50`.
    #[serde(default = "default_max_items_per_run")]
    pub max_items_per_run: usize,

    /// Optional LLM second opinion during score (**T-167**). Env:
    /// `LLM_SCORING_ENABLED`. Default `false` (requires `LLM_ENABLED=true` at runtime).
    #[serde(default)]
    pub llm_scoring_enabled: bool,

    /// Weight for deterministic points when merging. Env:
    /// `LLM_SCORING_DETERMINISTIC_WEIGHT`. Default `0.7`.
    #[serde(default = "default_llm_scoring_deterministic_weight")]
    pub llm_scoring_deterministic_weight: f32,

    /// Weight for LLM points when merging. Env:
    /// `LLM_SCORING_LLM_WEIGHT`. Default `0.3`.
    #[serde(default = "default_llm_scoring_llm_weight")]
    pub llm_scoring_llm_weight: f32,

    /// Toggle semantic embeddings (**T-247**). Env: `EMBEDDINGS_ENABLED`. Default `false`.
    #[serde(default)]
    pub embeddings_enabled: bool,

    /// Embedding model id (OpenAI-compatible `/embeddings`). Env: `EMBEDDING_MODEL`.
    pub embedding_model: Option<String>,

    /// Max extracted items embedded per CLI/CronJob pass. Env: `EMBED_BATCH_LIMIT`.
    /// Default `50`, clamped to `1..=MAX_EMBED_BATCH_LIMIT` (**T-256**).
    #[serde(default = "default_embed_batch_limit")]
    pub embed_batch_limit: i64,

    /// Rows embedded after each extract pass (tail). Env: `POST_EXTRACT_EMBED_TAIL_LIMIT`.
    /// Default `25` (**T-259**).
    #[serde(default = "default_post_extract_embed_tail_limit")]
    pub post_extract_embed_tail_limit: i64,
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

fn default_llm_max_rpm() -> u32 {
    DEFAULT_LLM_MAX_RPM
}

fn default_collect_concurrency() -> usize {
    2
}

fn default_max_items_per_run() -> usize {
    50
}
fn default_llm_scoring_deterministic_weight() -> f32 {
    0.7
}
fn default_llm_scoring_llm_weight() -> f32 {
    0.3
}

fn default_embed_batch_limit() -> i64 {
    DEFAULT_EMBED_BATCH_LIMIT
}

fn default_post_extract_embed_tail_limit() -> i64 {
    DEFAULT_POST_EXTRACT_EMBED_TAIL_LIMIT
}

impl AppConfig {
    /// Resolve embed batch size: CLI `--limit` overrides config/env (**T-256**).
    #[must_use]
    pub fn resolve_embed_batch_limit(&self, cli_override: Option<i64>) -> i64 {
        let base = cli_override.unwrap_or(self.embed_batch_limit);
        base.clamp(1, MAX_EMBED_BATCH_LIMIT)
    }

    /// Effective post-extract embed tail size (**T-259**).
    #[must_use]
    pub fn post_extract_embed_tail_limit(&self) -> i64 {
        self.post_extract_embed_tail_limit
            .clamp(1, MAX_EMBED_BATCH_LIMIT)
    }

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
                "LLM_MAX_RPM",
                "LLM_SCORING_ENABLED",
                "LLM_SCORING_DETERMINISTIC_WEIGHT",
                "LLM_SCORING_LLM_WEIGHT",
                "EMBEDDINGS_ENABLED",
                "EMBEDDING_MODEL",
                "EMBED_BATCH_LIMIT",
                "POST_EXTRACT_EMBED_TAIL_LIMIT",
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
            assert_eq!(cfg.collect_concurrency, 2);
            assert_eq!(cfg.max_items_per_run, 50);
            assert_eq!(cfg.embed_batch_limit, DEFAULT_EMBED_BATCH_LIMIT);
            assert_eq!(
                cfg.post_extract_embed_tail_limit(),
                DEFAULT_POST_EXTRACT_EMBED_TAIL_LIMIT
            );
            Ok(())
        });
    }

    #[test]
    fn post_extract_embed_tail_limit_from_env_and_clamp() {
        Jail::expect_with(|jail| {
            jail.clear_env();
            jail.set_env("POST_EXTRACT_EMBED_TAIL_LIMIT", "200");
            let cfg = AppConfig::from_env().expect("must load");
            assert_eq!(cfg.post_extract_embed_tail_limit(), MAX_EMBED_BATCH_LIMIT);
            jail.set_env("POST_EXTRACT_EMBED_TAIL_LIMIT", "10");
            let cfg = AppConfig::from_env().expect("must load");
            assert_eq!(cfg.post_extract_embed_tail_limit(), 10);
            Ok(())
        });
    }

    #[test]
    fn embed_batch_limit_from_env_and_clamp() {
        Jail::expect_with(|jail| {
            jail.clear_env();
            jail.set_env("EMBED_BATCH_LIMIT", "200");
            let cfg = AppConfig::from_env().expect("must load");
            assert_eq!(cfg.resolve_embed_batch_limit(None), MAX_EMBED_BATCH_LIMIT);
            assert_eq!(cfg.resolve_embed_batch_limit(Some(75)), 75);
            assert_eq!(cfg.resolve_embed_batch_limit(Some(0)), 1);
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
