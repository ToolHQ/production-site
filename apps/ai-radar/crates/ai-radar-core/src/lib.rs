//! AI Radar — core library.
//!
//! Hosts the domain model, repositories, `LLM` providers and pipeline orchestration
//! shared by `ai-radar-api` (HTTP) and `ai-radar-cli` (`CronJob` entrypoint).
//!
//! Modules are added incrementally as the program advances through epics
//! T-159..T-174 (see `docs/AI-RADAR-DECISIONS.md`).

#![forbid(unsafe_code)]
#![warn(clippy::pedantic, missing_docs)]
#![allow(clippy::module_name_repetitions)]

pub mod collector;
pub mod comparator;
pub mod curation;
pub mod config;
pub mod db;
pub mod domain;
pub mod extractor;
pub mod langfuse_export;
pub mod llm;
pub mod metrics;
pub mod pipeline;
pub mod repos;
pub mod scorer;
pub mod telemetry;
pub mod util;

/// Crate version exposed for telemetry and HTTP responses.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
