//! Repository traits and Postgres implementations.
//!
//! Every aggregate (sources, raw items, extracted items, scores,
//! feedback, digests) gets a trait describing the operations the rest
//! of the codebase relies on plus a Postgres implementation built on
//! the shared [`Database`](crate::db::Database) pool.
//!
//! Tests at the trait level are unit tests; the integration tests that
//! exercise the actual SQL live next to each implementation and are
//! gated behind the `db_integration` cfg or `#[ignore]` attribute so
//! `cargo test` runs cleanly without a Postgres available. CI plus the
//! `tools/harness/verify.sh rust-ai-radar` gate run them explicitly.

pub mod source;

pub use source::{PgSourceRepository, SourceRepository};
