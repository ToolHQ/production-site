//! GitHub adoption signals copied from `raw_items` into extracts (**T-230**).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::domain::RawItem;

/// Popularity band derived from GitHub stars.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StarsTier {
    /// Fewer than 100 stars.
    Niche,
    /// 100–999 stars.
    Growing,
    /// 1_000–9_999 stars.
    Popular,
    /// 10_000+ stars.
    Viral,
}

impl StarsTier {
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            StarsTier::Niche => "niche",
            StarsTier::Growing => "growing",
            StarsTier::Popular => "popular",
            StarsTier::Viral => "viral",
        }
    }
}

/// Recency band from last push / publish.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ActivityTier {
    /// Push within 30 days.
    Active,
    /// 31–90 days.
    Moderate,
    /// 91–180 days.
    Stale,
    /// Older than 180 days or unknown.
    Dormant,
}

impl ActivityTier {
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            ActivityTier::Active => "active",
            ActivityTier::Moderate => "moderate",
            ActivityTier::Stale => "stale",
            ActivityTier::Dormant => "dormant",
        }
    }
}

/// Normalized adoption block stored on `extracted_items.metadata_json.adoption`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AdoptionSnapshot {
    pub stars: Option<i64>,
    pub forks: Option<i64>,
    pub open_issues: Option<i64>,
    pub days_since_push: Option<i64>,
    pub stars_tier: StarsTier,
    pub activity_tier: ActivityTier,
    pub source: String,
}

impl AdoptionSnapshot {
    #[must_use]
    pub fn to_json(&self) -> Value {
        json!({
            "stars": self.stars,
            "forks": self.forks,
            "open_issues": self.open_issues,
            "days_since_push": self.days_since_push,
            "stars_tier": self.stars_tier.as_str(),
            "activity_tier": self.activity_tier.as_str(),
            "source": self.source,
        })
    }
}

#[must_use]
pub fn stars_tier(stars: i64) -> StarsTier {
    match stars {
        s if s >= 10_000 => StarsTier::Viral,
        s if s >= 1_000 => StarsTier::Popular,
        s if s >= 100 => StarsTier::Growing,
        _ => StarsTier::Niche,
    }
}

#[must_use]
pub fn activity_tier(days_since_push: Option<i64>) -> ActivityTier {
    match days_since_push {
        Some(d) if d <= 30 => ActivityTier::Active,
        Some(d) if d <= 90 => ActivityTier::Moderate,
        Some(d) if d <= 180 => ActivityTier::Stale,
        _ => ActivityTier::Dormant,
    }
}

/// Build adoption metadata from a collected `raw_items` row (no LLM).
#[must_use]
pub fn adoption_from_raw(raw: &RawItem) -> Option<AdoptionSnapshot> {
    let meta = &raw.metadata_json;
    let stars = meta.get("stargazers_count").and_then(json_i64);
    let forks = meta.get("forks_count").and_then(json_i64);
    let open_issues = meta.get("open_issues_count").and_then(json_i64);

    if stars.is_none() && forks.is_none() && open_issues.is_none() {
        return None;
    }

    let pushed_at = raw
        .published_at
        .or_else(|| parse_rfc3339(meta.get("pushed_at").and_then(|v| v.as_str())?));
    let days_since_push = pushed_at.map(|t| (Utc::now() - t).num_days().max(0));

    let stars_val = stars.unwrap_or(0);
    Some(AdoptionSnapshot {
        stars,
        forks,
        open_issues,
        days_since_push,
        stars_tier: stars_tier(stars_val),
        activity_tier: activity_tier(days_since_push),
        source: "github_metadata".into(),
    })
}

fn json_i64(v: &Value) -> Option<i64> {
    v.as_i64()
        .or_else(|| v.as_u64().and_then(|u| i64::try_from(u).ok()))
        .or_else(|| v.as_f64().map(|f| f as i64))
}

fn parse_rfc3339(s: &str) -> Option<DateTime<Utc>> {
    chrono::DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|dt| dt.with_timezone(&Utc))
}

/// Read adoption block from an extracted row (for scorer / comparator).
#[must_use]
pub fn adoption_from_extracted(metadata: &Value) -> Option<AdoptionSnapshot> {
    let obj = metadata.get("adoption")?;
    let stars_tier = match obj.get("stars_tier")?.as_str()? {
        "niche" => StarsTier::Niche,
        "growing" => StarsTier::Growing,
        "popular" => StarsTier::Popular,
        "viral" => StarsTier::Viral,
        _ => StarsTier::Niche,
    };
    let activity_tier = match obj.get("activity_tier")?.as_str()? {
        "active" => ActivityTier::Active,
        "moderate" => ActivityTier::Moderate,
        "stale" => ActivityTier::Stale,
        _ => ActivityTier::Dormant,
    };
    Some(AdoptionSnapshot {
        stars: obj.get("stars").and_then(json_i64),
        forks: obj.get("forks").and_then(json_i64),
        open_issues: obj.get("open_issues").and_then(json_i64),
        days_since_push: obj.get("days_since_push").and_then(json_i64),
        stars_tier,
        activity_tier,
        source: "extracted_metadata".into(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use uuid::Uuid;

    fn raw_with_meta(meta: Value) -> RawItem {
        RawItem {
            id: Uuid::new_v4(),
            source_id: Uuid::new_v4(),
            external_id: None,
            url: "https://github.com/o/r".into(),
            title: None,
            raw_content: "{}".into(),
            content_hash: "h".into(),
            status: crate::domain::RawItemStatus::Pending,
            metadata_json: meta,
            tool_key: None,
            canonical_url: None,
            published_at: Some(Utc::now() - chrono::Duration::days(10)),
            collected_at: Utc::now(),
        }
    }

    #[test]
    fn popular_repo_tier() {
        let snap = adoption_from_raw(&raw_with_meta(json!({
            "stargazers_count": 5000,
            "forks_count": 200
        })))
        .unwrap();
        assert_eq!(snap.stars_tier, StarsTier::Popular);
        assert_eq!(snap.activity_tier, ActivityTier::Active);
    }

    #[test]
    fn niche_repo_tier() {
        let snap = adoption_from_raw(&raw_with_meta(json!({"stargazers_count": 12}))).unwrap();
        assert_eq!(snap.stars_tier, StarsTier::Niche);
    }
}
