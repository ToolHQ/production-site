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

pub mod digest;
pub mod extracted_item;
pub mod feedback;
pub mod raw_item;
pub mod score;
pub mod source;

pub use digest::{DigestRepository, PgDigestRepository};
pub use extracted_item::{ExtractedItemRepository, PgExtractedItemRepository};
pub use feedback::{FeedbackRepository, PgFeedbackRepository};
pub use raw_item::{PgRawItemRepository, RawItemRepository};
pub use score::{PgScoreRepository, ScoreRepository};
pub use source::{PgSourceRepository, SourceRepository};
