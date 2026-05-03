//! Stub for future Langfuse export (T-172).
//!
//! Call once at process startup so operators see that export is intentionally
//! disabled in this build.

/// Emit a single structured warning: Langfuse is not configured.
#[inline]
pub fn log_not_configured() {
    tracing::warn!(
        target: "ai_radar::langfuse",
        "langfuse export is not configured"
    );
}
