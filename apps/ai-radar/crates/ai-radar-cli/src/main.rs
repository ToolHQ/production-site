//! AI Radar — CLI entrypoint.
//!
//! T-159 scaffold: only resolves the version string and parses an empty
//! command tree to validate the workspace links correctly. Real subcommands
//! (`collect`, `extract`, `score`, `digest`, `compare`, `reprocess`, `run-all`)
//! arrive in epics T-161, T-162, T-163, T-165, T-166, T-168, T-169, T-173.

#![forbid(unsafe_code)]
#![warn(clippy::pedantic)]

use clap::Parser;

#[derive(Debug, Parser)]
#[command(
    name = "ai-radar",
    version = ai_radar_core::VERSION,
    about = "AI Radar — Decision Engine for AI tooling curation",
    long_about = None,
)]
struct Cli {}

fn main() {
    let _ = Cli::parse();
    println!(
        "ai-radar {} (T-159 scaffold — subcommands pending)",
        ai_radar_core::VERSION
    );
}
