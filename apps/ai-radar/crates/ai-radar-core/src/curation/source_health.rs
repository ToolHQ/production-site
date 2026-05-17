//! Per-source health tiers for noise-aware scoring (**T-238**).

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

/// Health band derived from collect/extract yield.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SourceHealthTier {
    /// Low sample count — not enough signal.
    Unknown,
    /// Poll/collect errors recorded on the source row.
    Degraded,
    /// High failed or duplicate skip ratio.
    Noisy,
    /// Within normal operating bounds.
    Healthy,
}

impl SourceHealthTier {
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            SourceHealthTier::Unknown => "unknown",
            SourceHealthTier::Degraded => "degraded",
            SourceHealthTier::Noisy => "noisy",
            SourceHealthTier::Healthy => "healthy",
        }
    }
}

/// Aggregated counters for one monitored source.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SourceHealthSnapshot {
    pub source_id: Uuid,
    pub source_name: String,
    pub tier: SourceHealthTier,
    pub raw_total: i64,
    pub raw_failed: i64,
    pub raw_skipped: i64,
    pub extracted_total: i64,
    pub quality_warn: i64,
    pub last_error: Option<String>,
}

impl SourceHealthSnapshot {
    #[must_use]
    pub fn to_json(&self) -> Value {
        json!({
            "source_id": self.source_id,
            "source_name": self.source_name,
            "tier": self.tier.as_str(),
            "raw_total": self.raw_total,
            "raw_failed": self.raw_failed,
            "raw_skipped": self.raw_skipped,
            "extracted_total": self.extracted_total,
            "quality_warn": self.quality_warn,
            "last_error": self.last_error,
        })
    }
}

/// Classify a source from aggregate counters.
#[must_use]
pub fn health_tier(
    raw_total: i64,
    raw_failed: i64,
    raw_skipped: i64,
    last_error: Option<&str>,
) -> SourceHealthTier {
    if raw_total < 5 {
        return SourceHealthTier::Unknown;
    }
    if last_error.map(str::trim).is_some_and(|s| !s.is_empty()) {
        return SourceHealthTier::Degraded;
    }
    let fail_ratio = raw_failed as f64 / raw_total as f64;
    let denom = raw_total + raw_skipped;
    let skip_ratio = if denom > 0 {
        raw_skipped as f64 / denom as f64
    } else {
        0.0
    };
    if fail_ratio >= 0.25 || (skip_ratio >= 0.55 && raw_total >= 10) {
        SourceHealthTier::Noisy
    } else {
        SourceHealthTier::Healthy
    }
}

/// Build a snapshot from DB aggregates.
#[must_use]
pub fn snapshot_from_counts(
    source_id: Uuid,
    source_name: String,
    raw_total: i64,
    raw_failed: i64,
    raw_skipped: i64,
    extracted_total: i64,
    quality_warn: i64,
    last_error: Option<String>,
) -> SourceHealthSnapshot {
    let tier = health_tier(
        raw_total,
        raw_failed,
        raw_skipped,
        last_error.as_deref(),
    );
    SourceHealthSnapshot {
        source_id,
        source_name,
        tier,
        raw_total,
        raw_failed,
        raw_skipped,
        extracted_total,
        quality_warn,
        last_error,
    }
}

/// Read `metadata_json.source_health` from an extracted row.
#[must_use]
pub fn source_health_from_extracted(metadata: &Value) -> Option<SourceHealthSnapshot> {
    let obj = metadata.get("source_health")?;
    let source_id = obj.get("source_id")?.as_str()?.parse().ok()?;
    let tier = match obj.get("tier")?.as_str()? {
        "healthy" => SourceHealthTier::Healthy,
        "degraded" => SourceHealthTier::Degraded,
        "noisy" => SourceHealthTier::Noisy,
        _ => SourceHealthTier::Unknown,
    };
    Some(SourceHealthSnapshot {
        source_id,
        source_name: obj
            .get("source_name")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        tier,
        raw_total: obj.get("raw_total").and_then(json_i64).unwrap_or(0),
        raw_failed: obj.get("raw_failed").and_then(json_i64).unwrap_or(0),
        raw_skipped: obj.get("raw_skipped").and_then(json_i64).unwrap_or(0),
        extracted_total: obj.get("extracted_total").and_then(json_i64).unwrap_or(0),
        quality_warn: obj.get("quality_warn").and_then(json_i64).unwrap_or(0),
        last_error: obj
            .get("last_error")
            .and_then(|v| v.as_str())
            .map(str::to_string),
    })
}

fn json_i64(v: &Value) -> Option<i64> {
    v.as_i64()
        .or_else(|| v.as_u64().and_then(|u| i64::try_from(u).ok()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn noisy_on_high_fail_ratio() {
        assert_eq!(
            health_tier(100, 30, 0, None),
            SourceHealthTier::Noisy
        );
    }

    #[test]
    fn degraded_when_last_error_set() {
        assert_eq!(
            health_tier(50, 0, 0, Some("timeout")),
            SourceHealthTier::Degraded
        );
    }

    #[test]
    fn unknown_with_few_samples() {
        assert_eq!(health_tier(2, 0, 0, None), SourceHealthTier::Unknown);
    }
}
