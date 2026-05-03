//! Prometheus-compatible metric registration for pipelines (T-172).
//!
//! Increment macros are safe when no global recorder is installed (e.g. CLI
//! CronJob): they become no-ops. The HTTP API installs
//! `metrics-exporter-prometheus` so the same code paths emit counters there.

use std::time::Duration;

use metrics::{counter, describe_counter, describe_gauge, describe_histogram, gauge, histogram};

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
    describe_gauge!(
        "ai_radar_pending_raw_items",
        "raw_items rows in pending status awaiting extract"
    );
    describe_counter!(
        "ai_radar_sources_skipped_poll_total",
        "Sources not fetched because poll_interval has not elapsed since last_polled_at"
    );
    describe_counter!(
        "ai_radar_entries_rejected_total",
        "Domain rows dropped before insert (oversize, validation, …)"
    );
}

/// Refresh gauge from DB count (call from `/metrics` before render).
///
/// `f64` has a 52-bit mantissa; counts beyond ~9e15 lose exact integers in Prometheus,
/// which is acceptable for queue depth.
#[inline]
#[allow(clippy::cast_precision_loss)]
pub fn set_pending_raw_items_count(count: i64) {
    gauge!("ai_radar_pending_raw_items").set(count.max(0) as f64);
}

/// Emit counters and histogram after one `collect` pass completes.
pub fn record_collect_pass(
    filter: SourceType,
    collected: u64,
    skipped: u64,
    source_errors: u64,
    skipped_poll: u64,
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
    if skipped_poll > 0 {
        counter!(
            "ai_radar_sources_skipped_poll_total",
            "source_type" => source_type
        )
        .increment(skipped_poll);
    }
    histogram!("ai_radar_stage_duration_seconds", "stage" => "collect")
        .record(elapsed.as_secs_f64());
}

/// One feed entry rejected during collect (e.g. body larger than [`crate::util::limits::MAX_RAW_CONTENT_BYTES`]).
#[inline]
pub fn record_entry_rejected(source_type: SourceType, reason: &'static str) {
    let st = source_type.as_str();
    counter!(
        "ai_radar_entries_rejected_total",
        "source_type" => st,
        "reason" => reason
    )
    .increment(1);
}
