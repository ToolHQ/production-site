//! Domain entities mirroring the `ai_radar` schema.
//!
//! Each module exposes the strongly-typed Rust struct plus the value
//! objects (newtypes / enums) that map onto the Postgres CHECK
//! constraints, so a typo at compile time is the only way to insert a
//! malformed row.

pub mod source;

pub use source::{NewSource, Source, SourceType, SourceUpdate};
