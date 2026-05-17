//! Upstream collectors (`RSS`, GitHub, …).
//!
//! Each collector maps remote content into [`crate::domain::NewRawItem`] rows.

pub mod error;
pub mod github;
pub mod rss;
pub mod web;

pub use error::CollectError;

use async_trait::async_trait;

use crate::domain::{NewRawItem, Source};

/// Pluggable collector contract used by [`crate::pipeline::collect`].
#[async_trait]
pub trait Collector: Send + Sync {
    /// Pull the latest items for `source` and return insert payloads.
    ///
    /// Implementations must **not** touch Postgres — persistence happens in
    /// the pipeline after idempotent inserts.
    async fn collect(&self, source: &Source) -> Result<Vec<NewRawItem>, CollectError>;
}
