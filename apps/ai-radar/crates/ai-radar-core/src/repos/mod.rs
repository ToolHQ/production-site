//! Repository traits and Postgres implementations.
//!
//! Every aggregate (sources, raw items, extracted items, scores,
//! feedback, digests) gets a trait describing the operations the rest
//! of the codebase relies on plus a Postgres implementation built on
//! the shared [`Database`](crate::db::Database) pool.
//!
//! Tests at the trait level are unit tests; the integration tests that
//! exercise the actual SQL live next to each implementation and are
//! `#[ignore]`d so `cargo test --workspace` runs cleanly without a
//! Postgres available. CI plus the `tools/harness/verify.sh
//! rust-ai-radar` gate run them explicitly via
//! `cargo test --workspace -- --ignored --test-threads=1`.
//!
//! ## Why runtime-checked SQL (not the `sqlx::query!` macros)?
//!
//! Every query here uses `sqlx::query` / `sqlx::query_as` (runtime
//! validation against the live database) rather than the
//! compile-time-checked `query!` / `query_as!` macros. The trade-off
//! is intentional for the MVP:
//!
//! - **Builds anywhere**: `cargo build` works without `DATABASE_URL`
//!   and without committing the `.sqlx/` offline cache. The Docker
//!   build, the harness gate and CI agents run unchanged.
//! - **Schema regressions still catch fire**: every SQL statement is
//!   exercised by the `#[ignore]`d integration tests against the
//!   compose Postgres, so any drift between the migrations and the
//!   queries shows up the first time someone runs them.
//! - **Easy to upgrade later**: once the schema settles a follow-up
//!   epic can migrate the hottest queries to `query_as!` and commit
//!   the `.sqlx/` cache. The trait surface stays unchanged.

pub mod comparison;
pub mod digest;
pub mod extracted_item;
pub mod feedback;
pub mod raw_item;
pub mod score;
pub mod source;
pub mod stats;
pub mod tool_metrics_snapshot;

pub use comparison::{ComparisonRepository, PgComparisonRepository};
pub use digest::{DigestRepository, PgDigestRepository};
pub use extracted_item::{ExtractedItemRepository, PgExtractedItemRepository};
pub use feedback::{FeedbackDivergence, FeedbackRepository, PgFeedbackRepository};
pub use raw_item::{DuplicateCluster, PgRawItemRepository, RawItemRepository};
pub use score::{PgScoreRepository, ScoreRepository, ScoredItemSort};
pub use source::{PgSourceRepository, SourceRepository};
pub use stats::{load_pipeline_stats, PipelineStats};
pub use tool_metrics_snapshot::{
    NewToolMetricsSnapshot, PgToolMetricsSnapshotRepository, ToolMetricsSnapshotRepository,
};
