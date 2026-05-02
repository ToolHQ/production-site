//! Prometheus-compatible metric registration for pipelines (T-172).
//!
//! Increment macros are safe when no global recorder is installed (e.g. CLI
//! CronJob): they become no-ops. The HTTP API installs
//! `metrics-exporter-prometheus` so the same code paths emit counters there.

use std::time::Duration;

use metrics::{counter, describe_counter, describe_histogram, histogram};

use crate::domain::SourceType;

/// Register HELP strings once per process (after the Prometheus recorder is
/// installed in `ai-radar-api`).
pub fn describe_metrics() {
    describe_counter!(
        "ai_radar_collected_total",
        "Raw rows inserted per collect pass by source_type"
    );
    describe_counter!(
        "ai_radar_skipped_total",
        "Duplicate raw_items skipped by source_type"
    );
    describe_counter!(
        "ai_radar_errors_total",
        "Counted failures by pipeline stage"
    );
    describe_histogram!(
        "ai_radar_stage_duration_seconds",
        "Wall-clock duration of pipeline stages"
    );
}

/// Emit counters and histogram after one `collect` pass completes.
pub fn record_collect_pass(
    filter: SourceType,
    collected: u64,
    skipped: u64,
    source_errors: u64,
    elapsed: Duration,
) {
    let source_type = filter.as_str();
    counter!(
        "ai_radar_collected_total",
        "source_type" => source_type
    )
    .increment(collected);
    counter!(
        "ai_radar_skipped_total",
        "source_type" => source_type
    )
    .increment(skipped);
    if source_errors > 0 {
        counter!("ai_radar_errors_total", "stage" => "collect").increment(source_errors);
    }
    histogram!("ai_radar_stage_duration_seconds", "stage" => "collect")
        .record(elapsed.as_secs_f64());
}
