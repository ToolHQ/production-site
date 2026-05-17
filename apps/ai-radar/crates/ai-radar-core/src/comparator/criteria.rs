//! Map [`ExtractedItem`] + [`Score`] into 0–3 criteria (**T-168**).

use chrono::Utc;
use serde::{Deserialize, Serialize};

use crate::curation::adoption::{adoption_from_extracted, StarsTier};
use crate::domain::{ExtractedItem, Maturity, Score};

/// Six criteria, each scored 0–3.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct CriteriaScores {
    /// Self-hostable without mandatory SaaS.
    pub self_hosted: u8,
    /// Fits Kubernetes / cluster-first ops.
    pub k8s_friendly: u8,
    /// License clarity (OSS vs proprietary).
    pub license_clarity: u8,
    /// Product maturity signal.
    pub maturity: u8,
    /// Recency of upstream activity.
    pub last_activity: u8,
    /// Documentation / summary quality proxy.
    pub doc_quality: u8,
    /// Community adoption proxy (GitHub stars when present).
    pub community: u8,
}

/// Score criteria from structured fields (pure, unit-testable).
#[must_use]
pub fn score_criteria(item: &ExtractedItem, score: &Score) -> CriteriaScores {
    let _ = score; // reserved for future weighting hints
    CriteriaScores {
        self_hosted: score_self_hosted(item),
        k8s_friendly: score_k8s_friendly(item),
        license_clarity: score_license(item),
        maturity: score_maturity(item),
        last_activity: score_last_activity(item),
        doc_quality: score_doc_quality(item),
        community: score_community(item),
    }
}

fn score_self_hosted(item: &ExtractedItem) -> u8 {
    match item.self_hosted {
        Some(true) => 3,
        Some(false) if item.saas_only == Some(true) => 0,
        Some(false) => 1,
        None => 1,
    }
}

fn score_k8s_friendly(item: &ExtractedItem) -> u8 {
    let stack = item.stack_fit.as_deref().unwrap_or("").to_lowercase();
    let meta = item.metadata_json.to_string().to_lowercase();
    let k8s_hints = ["k8s", "kubernetes", "helm", "operator", "cluster"];
    let hits = k8s_hints
        .iter()
        .filter(|h| stack.contains(*h) || meta.contains(*h))
        .count();
    match hits {
        0 => 1,
        1 => 2,
        _ => 3,
    }
}

fn score_license(item: &ExtractedItem) -> u8 {
    let lic = item.license.as_deref().unwrap_or("").trim().to_lowercase();
    if lic.is_empty() {
        return 1;
    }
    if lic.contains("proprietary") || lic.contains("commercial") {
        return 0;
    }
    if lic.contains("apache") || lic.contains("mit") || lic.contains("bsd") || lic.contains("gpl") {
        return 3;
    }
    2
}

fn score_maturity(item: &ExtractedItem) -> u8 {
    match item.maturity {
        Some(Maturity::Mature) | Some(Maturity::Stable) => 3,
        Some(Maturity::Beta) => 2,
        Some(Maturity::Experimental) => 1,
        Some(Maturity::Deprecated) => 0,
        None => 1,
    }
}

fn score_community(item: &ExtractedItem) -> u8 {
    let Some(adoption) = adoption_from_extracted(&item.metadata_json) else {
        return 1;
    };
    match adoption.stars_tier {
        StarsTier::Viral => 3,
        StarsTier::Popular => 3,
        StarsTier::Growing => 2,
        StarsTier::Niche => 1,
    }
}

fn score_last_activity(item: &ExtractedItem) -> u8 {
    if let Some(adoption) = adoption_from_extracted(&item.metadata_json) {
        if let Some(days) = adoption.days_since_push {
            return bucket_days(days);
        }
    }
    if let Some(days) = item
        .metadata_json
        .get("days_since_activity")
        .and_then(|v| v.as_i64())
    {
        return bucket_days(days);
    }
    let age_days = (Utc::now() - item.created_at).num_days();
    bucket_days(age_days)
}

fn bucket_days(days: i64) -> u8 {
    match days {
        d if d <= 30 => 3,
        d if d <= 90 => 2,
        d if d <= 180 => 1,
        _ => 0,
    }
}

fn score_doc_quality(item: &ExtractedItem) -> u8 {
    let summary_len = item.summary.as_deref().map(str::len).unwrap_or(0);
    let problem_len = item.problem_solved.as_deref().map(str::len).unwrap_or(0);
    let total = summary_len + problem_len;
    match total {
        0 => 0,
        1..=80 => 1,
        81..=200 => 2,
        _ => 3,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::{Decision, RiskLevel};

    fn item() -> ExtractedItem {
        ExtractedItem {
            id: uuid::Uuid::new_v4(),
            raw_item_id: uuid::Uuid::new_v4(),
            version: 1,
            extractor: "llm-v2".into(),
            tool_name: Some("ToolX".into()),
            category: Some("MCP".into()),
            summary: Some("A well documented MCP server for Kubernetes deployments.".into()),
            problem_solved: Some("Connects agents".into()),
            self_hosted: Some(true),
            saas_only: Some(false),
            license: Some("MIT".into()),
            maturity: Some(Maturity::Beta),
            risk_level: Some(RiskLevel::Low),
            stack_fit: Some("Helm chart for k8s".into()),
            metadata_json: serde_json::json!({"days_since_activity": 14}),
            created_at: Utc::now(),
        }
    }

    fn score() -> Score {
        Score {
            id: uuid::Uuid::new_v4(),
            extracted_item_id: uuid::Uuid::new_v4(),
            score: 0.75,
            decision: Decision::Test,
            next_step: None,
            reasons_json: serde_json::json!([]),
            risks_json: serde_json::json!([]),
            scoring_version: "deterministic-v1".into(),
            metadata_json: serde_json::json!({}),
            created_at: Utc::now(),
        }
    }

    #[test]
    fn criteria_are_bounded() {
        let c = score_criteria(&item(), &score());
        assert!(c.self_hosted <= 3);
        assert!(c.doc_quality >= 1);
    }
}
