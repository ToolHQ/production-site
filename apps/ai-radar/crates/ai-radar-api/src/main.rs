//! AI Radar — HTTP API binary entrypoint.
//!
//! At T-159 (bootstrap) this binary intentionally does the minimum work
//! required to validate the workspace builds and a `cargo run` succeeds.
//! Real router/server wiring lands later in T-159 (Axum `/health`) and
//! subsequent epics extend it (sources, items, digests, feedback, metrics).

#![forbid(unsafe_code)]
#![warn(clippy::pedantic)]

fn main() {
    println!(
        "ai-radar-api {} (T-159 scaffold — server wiring pending)",
        ai_radar_core::VERSION
    );
}
