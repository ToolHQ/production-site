//! Post-extract quality scoring (**T-232**).
//!
//! Deterministic completeness check before persisting `extracted_items` or
//! promoting noisy rows to the score pipeline.

use serde::{Deserialize, Serialize};

use super::schema::ExtractedFields;

/// Minimum summary length for full credit.
pub const QUALITY_SUMMARY_MIN_LEN: usize = 80;
/// Minimum `problem_solved` length for credit.
pub const QUALITY_PROBLEM_MIN_LEN: usize = 20;

/// Outcome band for operator automation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum QualityTier {
    /// Score ≥ 70 — proceed normally.
    Pass,
    /// Score 40–69 — persist with `quality_warn` / `low_confidence`.
    Warn,
    /// Score < 40 — reject; raw item marked `failed`.
    Reject,
}

/// Result of [`assess_extract_quality`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QualityReport {
    /// Integer completeness score in `[0, 100]`.
    pub score: u8,
    /// Band used by the extract pipeline.
    pub tier: QualityTier,
    /// Field names that did not meet thresholds (for logs / metadata).
    pub missing: Vec<String>,
    /// Non-blocking issues (e.g. generic category).
    pub warnings: Vec<String>,
}

impl QualityReport {
    /// Serialize into `metadata_json.extract_quality` on extracted rows.
    #[must_use]
    pub fn to_metadata(&self) -> serde_json::Value {
        serde_json::json!({
            "score": self.score,
            "tier": tier_label(self.tier),
            "missing": self.missing,
            "warnings": self.warnings,
        })
    }
}

fn tier_label(tier: QualityTier) -> &'static str {
    match tier {
        QualityTier::Pass => "pass",
        QualityTier::Warn => "warn",
        QualityTier::Reject => "reject",
    }
}

fn tier_from_score(score: u8) -> QualityTier {
    match score {
        0..=39 => QualityTier::Reject,
        40..=69 => QualityTier::Warn,
        _ => QualityTier::Pass,
    }
}

fn is_meaningful_tool_name(name: &str) -> bool {
    let t = name.trim();
    t.len() >= 2 && !matches!(t.to_ascii_lowercase().as_str(), "n/a" | "na" | "unknown" | "tbd")
}

fn is_specific_category(cat: &str) -> bool {
    let c = cat.trim().to_ascii_lowercase();
    !c.is_empty()
        && !matches!(
            c.as_str(),
            "other"
                | "misc"
                | "miscellaneous"
                | "general"
                | "unknown"
                | "n/a"
                | "na"
                | "uncategorized"
                | "various"
        )
}

/// Score LLM-extracted fields for completeness (pure, unit-testable).
#[must_use]
pub fn assess_extract_quality(fields: &ExtractedFields) -> QualityReport {
    let mut points: u16 = 0;
    let mut missing = Vec::new();
    let mut warnings = Vec::new();

    // tool_name — 25
    if fields
        .tool_name
        .as_deref()
        .is_some_and(is_meaningful_tool_name)
    {
        points += 25;
    } else {
        missing.push("tool_name".into());
    }

    // category — 20
    if let Some(cat) = fields.category.as_deref().filter(|c| !c.trim().is_empty()) {
        if is_specific_category(cat) {
            points += 20;
        } else {
            points += 8;
            warnings.push("generic_category".into());
            missing.push("specific_category".into());
        }
    } else {
        missing.push("category".into());
    }

    // summary — 25
    if fields
        .summary
        .as_deref()
        .is_some_and(|s| s.trim().len() >= QUALITY_SUMMARY_MIN_LEN)
    {
        points += 25;
    } else if fields.summary.as_deref().is_some_and(|s| !s.trim().is_empty()) {
        points += 10;
        missing.push("summary_length".into());
    } else {
        missing.push("summary".into());
    }

    // problem_solved — 15
    if fields
        .problem_solved
        .as_deref()
        .is_some_and(|s| s.trim().len() >= QUALITY_PROBLEM_MIN_LEN)
    {
        points += 15;
    } else if fields
        .problem_solved
        .as_deref()
        .is_some_and(|s| !s.trim().is_empty())
    {
        points += 5;
        missing.push("problem_solved_length".into());
    } else {
        missing.push("problem_solved".into());
    }

    // hosting signal — 10
    if fields.self_hosted.is_some() || fields.saas_only.is_some() {
        points += 10;
    } else {
        missing.push("hosting_flags".into());
    }

    // optional depth — 5
    if fields.license.as_deref().is_some_and(|s| !s.trim().is_empty())
        || fields.maturity.as_deref().is_some_and(|s| !s.trim().is_empty())
        || fields
            .stack_fit
            .as_deref()
            .is_some_and(|s| !s.trim().is_empty())
    {
        points += 5;
    } else {
        missing.push("license_or_maturity_or_stack".into());
    }

    let score = points.min(100) as u8;
    let tier = tier_from_score(score);

    QualityReport {
        score,
        tier,
        missing,
        warnings,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fields(partial: ExtractedFields) -> ExtractedFields {
        partial
    }

    fn rich() -> ExtractedFields {
        ExtractedFields {
            title: Some("T".into()),
            tool_name: Some("Ollama".into()),
            category: Some("LLM runtime".into()),
            problem_solved: Some("Run local LLMs on developer machines with low ops overhead.".into()),
            target_users: None,
            stack_fit: Some("kubernetes".into()),
            self_hosted: Some(true),
            saas_only: Some(false),
            license: Some("MIT".into()),
            maturity: Some("stable".into()),
            risk_level: None,
            summary: Some("A".repeat(QUALITY_SUMMARY_MIN_LEN)),
            key_points: None,
            recommended_action: None,
        }
    }

    #[test]
    fn rich_extract_scores_pass() {
        let r = assess_extract_quality(&rich());
        assert_eq!(r.tier, QualityTier::Pass);
        assert!(r.score >= 70, "score={}", r.score);
    }

    #[test]
    fn empty_extract_scores_reject() {
        let r = assess_extract_quality(&fields(ExtractedFields {
            title: None,
            tool_name: None,
            category: None,
            problem_solved: None,
            target_users: None,
            stack_fit: None,
            self_hosted: None,
            saas_only: None,
            license: None,
            maturity: None,
            risk_level: None,
            summary: None,
            key_points: None,
            recommended_action: None,
        }));
        assert_eq!(r.tier, QualityTier::Reject);
        assert!(r.score < 40);
    }

    #[test]
    fn partial_extract_scores_warn() {
        let r = assess_extract_quality(&fields(ExtractedFields {
            title: None,
            tool_name: Some("acme".into()),
            category: Some("other".into()),
            problem_solved: None,
            target_users: None,
            stack_fit: None,
            self_hosted: Some(false),
            saas_only: None,
            license: None,
            maturity: None,
            risk_level: None,
            summary: Some("Too short for full credit.".into()),
            key_points: None,
            recommended_action: None,
        }));
        assert_eq!(r.tier, QualityTier::Warn);
        assert!((40..70).contains(&r.score), "score={}", r.score);
    }
}
