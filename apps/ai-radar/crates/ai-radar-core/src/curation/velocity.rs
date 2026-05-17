//! Popularity velocity from `tool_metrics_snapshots` (**T-234**).

use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::curation::adoption::AdoptionSnapshot;
use crate::domain::RawItem;
use crate::repos::{
    NewToolMetricsSnapshot, PgToolMetricsSnapshotRepository, ToolMetricsSnapshotRepository,
};

/// Trend band from 7-day star delta.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VelocityTier {
    /// Δ stars ≥ 1_000 or strong relative growth.
    Spike,
    /// Δ stars ≥ 100.
    Growing,
    /// Between -100 and 100.
    Flat,
    /// Δ stars ≤ -100.
    Declining,
    /// No baseline sample in lookback window.
    Unknown,
}

impl VelocityTier {
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            VelocityTier::Spike => "spike",
            VelocityTier::Growing => "growing",
            VelocityTier::Flat => "flat",
            VelocityTier::Declining => "declining",
            VelocityTier::Unknown => "unknown",
        }
    }
}

/// Computed velocity for enrichment.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VelocitySnapshot {
    pub stars_delta_7d: Option<i64>,
    pub velocity_tier: VelocityTier,
}

/// Default lookback for star velocity.
pub const VELOCITY_WINDOW_DAYS: i64 = 7;

#[must_use]
pub fn velocity_tier(current_stars: i64, baseline_stars: Option<i64>) -> VelocitySnapshot {
    let Some(base) = baseline_stars else {
        return VelocitySnapshot {
            stars_delta_7d: None,
            velocity_tier: VelocityTier::Unknown,
        };
    };
    let delta = current_stars - base;
    let tier = if delta >= 1_000 || (delta >= 100 && base > 0 && delta * 100 / base >= 25) {
        VelocityTier::Spike
    } else if delta >= 100 {
        VelocityTier::Growing
    } else if delta <= -100 {
        VelocityTier::Declining
    } else {
        VelocityTier::Flat
    };
    VelocitySnapshot {
        stars_delta_7d: Some(delta),
        velocity_tier: tier,
    }
}

/// Merge velocity fields into an adoption block for metadata JSON.
#[must_use]
pub fn enrich_adoption(mut adoption: AdoptionSnapshot, velocity: &VelocitySnapshot) -> AdoptionSnapshot {
    adoption.stars_delta_7d = velocity.stars_delta_7d;
    adoption.velocity_tier = velocity.velocity_tier;
    adoption
}

/// Record a GitHub metrics sample when `tool_key` and stars are present.
///
/// # Errors
///
/// Propagates repository errors.
pub async fn record_metrics_snapshot(
    snapshots: &PgToolMetricsSnapshotRepository,
    tool_key: &str,
    source_id: uuid::Uuid,
    metadata: Option<&Value>,
) -> Result<(), crate::db::RepoError> {
    let Some(meta) = metadata else {
        return Ok(());
    };
    let stars = meta.get("stargazers_count").and_then(json_i64);
    if stars.is_none() && meta.get("forks_count").is_none() {
        return Ok(());
    }
    snapshots
        .insert(&NewToolMetricsSnapshot {
            tool_key: tool_key.to_string(),
            source_id: Some(source_id),
            stars,
            forks: meta.get("forks_count").and_then(json_i64),
            open_issues: meta.get("open_issues_count").and_then(json_i64),
            collected_at: Utc::now(),
        })
        .await
}

/// Compute velocity for a raw row (records snapshot first).
///
/// # Errors
///
/// Propagates repository errors.
pub async fn velocity_for_raw(
    snapshots: &PgToolMetricsSnapshotRepository,
    raw: &RawItem,
) -> Result<VelocitySnapshot, crate::db::RepoError> {
    let Some(tool_key) = raw.tool_key.as_deref() else {
        return Ok(VelocitySnapshot {
            stars_delta_7d: None,
            velocity_tier: VelocityTier::Unknown,
        });
    };
    record_metrics_snapshot(snapshots, tool_key, raw.source_id, Some(&raw.metadata_json)).await?;
    let stars = raw
        .metadata_json
        .get("stargazers_count")
        .and_then(json_i64)
        .unwrap_or(0);
    let baseline = snapshots
        .stars_baseline(tool_key, Utc::now(), VELOCITY_WINDOW_DAYS)
        .await?;
    Ok(velocity_tier(stars, baseline))
}

fn json_i64(v: &Value) -> Option<i64> {
    v.as_i64()
        .or_else(|| v.as_u64().and_then(|u| i64::try_from(u).ok()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spike_on_large_delta() {
        let v = velocity_tier(10_000, Some(8_000));
        assert_eq!(v.velocity_tier, VelocityTier::Spike);
        assert_eq!(v.stars_delta_7d, Some(2_000));
    }

    #[test]
    fn declining_on_negative_delta() {
        let v = velocity_tier(500, Some(700));
        assert_eq!(v.velocity_tier, VelocityTier::Declining);
    }

    #[test]
    fn unknown_without_baseline() {
        let v = velocity_tier(100, None);
        assert_eq!(v.velocity_tier, VelocityTier::Unknown);
    }
}
