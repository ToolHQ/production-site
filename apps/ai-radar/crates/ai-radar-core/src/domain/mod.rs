//! Domain entities mirroring the `ai_radar` schema.
//!
//! Each module exposes the strongly-typed Rust struct plus the value
//! objects (newtypes / enums) that map onto the Postgres CHECK
//! constraints, so a typo at compile time is the only way to insert a
//! malformed row.

pub mod comparison;
pub mod digest;
pub mod explorer;
pub mod extracted_item;
pub mod feedback;
pub mod raw_item;
pub mod score;
pub mod source;

pub use comparison::{Comparison, NewComparison};
pub use digest::{Digest, DigestType, NewDigest};
pub use explorer::{AdoptionSummary, ScoredItemSummary};
pub use extracted_item::{ExtractedItem, Maturity, NewExtractedItem, RiskLevel};
pub use feedback::{Feedback, FeedbackType, NewFeedback};
pub use raw_item::{NewRawItem, RawItem, RawItemStatus};
pub use score::{Decision, NewScore, Score};
pub use source::{NewSource, Source, SourceType, SourceUpdate};
