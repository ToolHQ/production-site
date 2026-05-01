//! Axum middlewares scoped to the `ai-radar-api` binary.

pub mod request_id;

pub use request_id::{request_id_middleware, RequestId};

// `REQUEST_ID_HEADER` is intentionally not re-exported here: it is only
// referenced from inside the `request_id` module and from `#[cfg(test)]`
// blocks, which already access it via `request_id::REQUEST_ID_HEADER`.
