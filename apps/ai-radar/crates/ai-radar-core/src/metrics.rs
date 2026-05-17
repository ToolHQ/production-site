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
    describe_counter!(
        "ai_radar_extracted_total",
        "raw_items successfully promoted to extracted_items by extract pass"
    );
    describe_counter!(
        "ai_radar_extract_failed_total",
        "raw_items marked failed after extract pass"
    );
    describe_counter!(
        "ai_radar_extract_quality_warn_total",
        "extracted_items persisted with quality_warn (score 40-69)"
    );
    describe_counter!(
        "ai_radar_extract_quality_rejected_total",
        "raw_items rejected by extract quality gate (score < 40)"
    );
    describe_histogram!(
        "ai_radar_extract_quality_score",
        "Completeness score 0-100 assigned at extract time"
    );
    describe_counter!(
        "ai_radar_entity_duplicate_skipped_total",
        "raw_items marked skipped as cross-source duplicates (T-231)"
    );
    describe_counter!(
        "ai_radar_scored_total",
        "extracted_items scored successfully in score pass"
    );
    describe_counter!(
        "ai_radar_score_failed_total",
        "score inserts that failed in score pass"
    );
    describe_counter!(
        "ai_radar_adoption_tier_total",
        "extracted_items scored with GitHub adoption metadata (T-230)"
    );
    describe_counter!(
        "ai_radar_velocity_tier_total",
        "extracted_items scored with GitHub velocity metadata (T-234)"
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

/// Emit counters after one `score` pass completes.
pub fn record_score_pass(scored: u64, failed: u64, elapsed: Duration) {
    counter!("ai_radar_scored_total").increment(scored);
    counter!("ai_radar_score_failed_total").increment(failed);
    if failed > 0 {
        counter!("ai_radar_errors_total", "stage" => "score").increment(failed);
    }
    histogram!("ai_radar_stage_duration_seconds", "stage" => "score").record(elapsed.as_secs_f64());
}

/// Emit counters after one `extract` pass completes.
pub fn record_extract_pass(
    extracted: u64,
    failed: u64,
    quality_warn: u64,
    quality_rejected: u64,
    elapsed: Duration,
) {
    counter!("ai_radar_extracted_total").increment(extracted);
    counter!("ai_radar_extract_failed_total").increment(failed);
    if quality_warn > 0 {
        counter!("ai_radar_extract_quality_warn_total").increment(quality_warn);
    }
    if quality_rejected > 0 {
        counter!("ai_radar_extract_quality_rejected_total").increment(quality_rejected);
    }
    if failed > 0 {
        counter!("ai_radar_errors_total", "stage" => "extract").increment(failed);
    }
    histogram!("ai_radar_stage_duration_seconds", "stage" => "extract")
        .record(elapsed.as_secs_f64());
}

/// Record one extract completeness score (histogram bucket).
#[inline]
#[allow(clippy::cast_precision_loss)]
pub fn record_extract_quality_score(score: u8) {
    histogram!("ai_radar_extract_quality_score").record(f64::from(score));
}

/// Increment warn-tier counter for a single item.
pub fn record_extract_quality_warn() {
    counter!("ai_radar_extract_quality_warn_total").increment(1);
}

/// Increment reject-tier counter for a single item.
pub fn record_extract_quality_rejected(score: u8) {
    let _ = score;
    counter!("ai_radar_extract_quality_rejected_total").increment(1);
}

/// Cross-source duplicate marked during entity resolution.
pub fn record_entity_duplicate_skipped() {
    counter!("ai_radar_entity_duplicate_skipped_total").increment(1);
}

/// One scored item that carried adoption metadata (stars tier label).
pub fn record_adoption_tier(decision: &str, stars_tier: &str) {
    counter!(
        "ai_radar_adoption_tier_total",
        "decision" => decision.to_string(),
        "stars_tier" => stars_tier.to_string()
    )
    .increment(1);
}

/// One scored item that carried velocity metadata (**T-234**).
pub fn record_velocity_tier(decision: &str, velocity_tier: &str) {
    counter!(
        "ai_radar_velocity_tier_total",
        "decision" => decision.to_string(),
        "velocity_tier" => velocity_tier.to_string()
    )
    .increment(1);
}

/// One feed entry rejected during collect (e.g. body larger than [`crate::util::limits::MAX_RAW_CONTENT_BYTES`]).
pub fn record_entry_rejected(source_type: SourceType, reason: &'static str) {
    let st = source_type.as_str();
    counter!(
        "ai_radar_entries_rejected_total",
        "source_type" => st,
        "reason" => reason
    )
    .increment(1);
}
