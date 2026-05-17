//! Deterministic scoring rules (`deterministic-v1`) derived from `docs/AI-RADAR-ROADMAP.md`.

use crate::curation::adoption::{adoption_from_extracted, ActivityTier, StarsTier};
use crate::curation::velocity::VelocityTier;
use crate::domain::{ExtractedItem, Maturity, RiskLevel};

/// Predicate evaluated against an [`ExtractedItem`].
pub type RulePredicate = fn(&ExtractedItem) -> bool;

/// One additive rule with human-readable audit text.
#[derive(Debug, Clone, Copy)]
pub struct Rule {
    /// Stable id stored in `scores.metadata_json` audits.
    pub id: &'static str,
    /// Points added when the predicate matches (may be negative).
    pub weight: i32,
    /// Predicate on the extracted row.
    pub predicate: RulePredicate,
    /// Explanation appended to `reasons_json`.
    pub reason: &'static str,
    /// Optional risk label appended to `risks_json` when matched.
    pub risk: Option<&'static str>,
}

fn lc(s: &str) -> String {
    s.to_lowercase()
}

fn has_problem(item: &ExtractedItem) -> bool {
    item.problem_solved
        .as_deref()
        .map(str::trim)
        .is_some_and(|s| s.len() >= 25)
}

fn self_hosted_yes(item: &ExtractedItem) -> bool {
    item.self_hosted == Some(true)
}

fn k8s_fit(item: &ExtractedItem) -> bool {
    item.stack_fit.as_deref().is_some_and(|s| {
        let t = lc(s);
        t.contains("k8") || t.contains("kubernetes")
    })
}

fn structured_identity(item: &ExtractedItem) -> bool {
    item.tool_name
        .as_deref()
        .is_some_and(|t| !t.trim().is_empty())
        && item
            .category
            .as_deref()
            .is_some_and(|c| !c.trim().is_empty())
}

fn rich_summary(item: &ExtractedItem) -> bool {
    item.summary
        .as_deref()
        .is_some_and(|s| s.trim().len() >= 80)
}

fn category_present(item: &ExtractedItem) -> bool {
    item.category
        .as_deref()
        .is_some_and(|c| !c.trim().is_empty())
}

fn cost_or_productivity_signal(item: &ExtractedItem) -> bool {
    let blob = [
        item.summary.as_deref(),
        item.problem_solved.as_deref(),
        item.stack_fit.as_deref(),
    ]
    .into_iter()
    .flatten()
    .collect::<Vec<_>>()
    .join(" ");
    let t = lc(&blob);
    t.contains("cost")
        || t.contains("save")
        || t.contains("reduce")
        || t.contains("custo")
        || t.contains("econom")
        || t.contains("productiv")
        || t.contains("developer")
}

fn permissive_license(item: &ExtractedItem) -> bool {
    item.license.as_deref().is_some_and(|s| {
        let t = lc(s);
        t.contains("mit")
            || t.contains("apache")
            || t.contains("bsd")
            || t.contains("isc")
            || t.contains("mpl")
    })
}

fn mature(item: &ExtractedItem) -> bool {
    matches!(item.maturity, Some(Maturity::Stable | Maturity::Mature))
}

fn low_risk(item: &ExtractedItem) -> bool {
    item.risk_level == Some(RiskLevel::Low)
}

fn deep_stack_notes(item: &ExtractedItem) -> bool {
    item.stack_fit
        .as_deref()
        .is_some_and(|s| s.trim().len() >= 40)
}

fn saas_only_lockin(item: &ExtractedItem) -> bool {
    item.saas_only == Some(true) && item.self_hosted != Some(true)
}

fn high_risk(item: &ExtractedItem) -> bool {
    item.risk_level == Some(RiskLevel::High)
}

fn deprecated(item: &ExtractedItem) -> bool {
    item.maturity == Some(Maturity::Deprecated)
}

fn superficial(item: &ExtractedItem) -> bool {
    item.tool_name.as_deref().map_or("", str::trim).is_empty()
        || item.summary.as_deref().map_or(0, |s| s.trim().len()) < 35
}

fn proprietary_license(item: &ExtractedItem) -> bool {
    item.license.as_deref().is_some_and(|s| {
        let t = lc(s);
        t.contains("proprietary") || t.contains("closed source") || t.contains("commercial only")
    })
}

fn weak_signals(item: &ExtractedItem) -> bool {
    item.stack_fit.as_deref().map_or("", str::trim).is_empty()
        && item.category.as_deref().map_or("", str::trim).is_empty()
}

fn experimental(item: &ExtractedItem) -> bool {
    item.maturity == Some(Maturity::Experimental)
}

fn adoption_popular(item: &ExtractedItem) -> bool {
    adoption_from_extracted(&item.metadata_json).is_some_and(|a| {
        matches!(a.stars_tier, StarsTier::Popular | StarsTier::Viral)
    })
}

fn adoption_growing(item: &ExtractedItem) -> bool {
    adoption_from_extracted(&item.metadata_json)
        .is_some_and(|a| a.stars_tier == StarsTier::Growing)
}

fn adoption_active(item: &ExtractedItem) -> bool {
    adoption_from_extracted(&item.metadata_json)
        .is_some_and(|a| a.activity_tier == ActivityTier::Active)
}

fn adoption_dormant(item: &ExtractedItem) -> bool {
    adoption_from_extracted(&item.metadata_json)
        .is_some_and(|a| a.activity_tier == ActivityTier::Dormant)
}

fn velocity_spike(item: &ExtractedItem) -> bool {
    adoption_from_extracted(&item.metadata_json)
        .is_some_and(|a| a.velocity_tier == VelocityTier::Spike)
}

fn velocity_stale(item: &ExtractedItem) -> bool {
    adoption_from_extracted(&item.metadata_json).is_some_and(|a| {
        a.velocity_tier == VelocityTier::Declining
            || (a.velocity_tier == VelocityTier::Flat
                && matches!(a.activity_tier, ActivityTier::Stale | ActivityTier::Dormant))
    })
}

fn hype_without_substance(item: &ExtractedItem) -> bool {
    item.summary.as_deref().is_some_and(|s| {
        let t = lc(s);
        (t.contains("best") || t.contains("#1") || t.contains("ultimate")) && s.len() < 100
    })
}

fn confusing_license(item: &ExtractedItem) -> bool {
    item.license.as_deref().is_none_or(|s| s.trim().is_empty())
}

/// Ruleset `deterministic-v1` (hardcoded; see roadmap “Scorer” section).
pub static RULES_V1: &[Rule] = &[
    Rule {
        id: "problem_filled",
        weight: 5,
        predicate: has_problem,
        reason: "Clear problem statement / use case captured",
        risk: None,
    },
    Rule {
        id: "self_hosted",
        weight: 4,
        predicate: self_hosted_yes,
        reason: "Self-hostable (fits constrained cluster policy)",
        risk: None,
    },
    Rule {
        id: "k8s_fit",
        weight: 4,
        predicate: k8s_fit,
        reason: "Kubernetes / platform fit mentioned",
        risk: None,
    },
    Rule {
        id: "structured_identity",
        weight: 3,
        predicate: structured_identity,
        reason: "Tool name and category present (structured extraction)",
        risk: None,
    },
    Rule {
        id: "rich_summary",
        weight: 3,
        predicate: rich_summary,
        reason: "Rich summary text (likely real signal)",
        risk: None,
    },
    Rule {
        id: "category_present",
        weight: 3,
        predicate: category_present,
        reason: "Category label present",
        risk: None,
    },
    Rule {
        id: "cost_productivity",
        weight: 3,
        predicate: cost_or_productivity_signal,
        reason: "Cost / productivity angle detected in text",
        risk: None,
    },
    Rule {
        id: "permissive_license",
        weight: 2,
        predicate: permissive_license,
        reason: "Permissive / well-known open license",
        risk: None,
    },
    Rule {
        id: "mature",
        weight: 2,
        predicate: mature,
        reason: "Stable or mature lifecycle stage",
        risk: None,
    },
    Rule {
        id: "low_risk",
        weight: 2,
        predicate: low_risk,
        reason: "Low operational risk grade",
        risk: None,
    },
    Rule {
        id: "deep_stack_notes",
        weight: 2,
        predicate: deep_stack_notes,
        reason: "Detailed stack / ops notes",
        risk: None,
    },
    Rule {
        id: "adoption_popular",
        weight: 3,
        predicate: adoption_popular,
        reason: "Strong GitHub adoption (1k+ stars)",
        risk: None,
    },
    Rule {
        id: "adoption_growing",
        weight: 1,
        predicate: adoption_growing,
        reason: "Growing GitHub traction (100+ stars)",
        risk: None,
    },
    Rule {
        id: "adoption_active",
        weight: 2,
        predicate: adoption_active,
        reason: "Recent upstream activity (push within 30d)",
        risk: None,
    },
    Rule {
        id: "velocity_spike",
        weight: 2,
        predicate: velocity_spike,
        reason: "Rapid GitHub star growth (7d velocity spike)",
        risk: None,
    },
    Rule {
        id: "velocity_stale",
        weight: -2,
        predicate: velocity_stale,
        reason: "Declining or flat star velocity with stale upstream",
        risk: Some("stagnant_momentum"),
    },
    Rule {
        id: "adoption_dormant",
        weight: -3,
        predicate: adoption_dormant,
        reason: "Stale upstream activity (>180d since push)",
        risk: Some("stale_upstream"),
    },
    Rule {
        id: "saas_lockin",
        weight: -5,
        predicate: saas_only_lockin,
        reason: "SaaS-only without self-host path",
        risk: Some("saas_lock_in"),
    },
    Rule {
        id: "high_risk",
        weight: -5,
        predicate: high_risk,
        reason: "High risk grade",
        risk: Some("high_risk"),
    },
    Rule {
        id: "deprecated",
        weight: -4,
        predicate: deprecated,
        reason: "Deprecated maturity",
        risk: Some("deprecated_project"),
    },
    Rule {
        id: "superficial",
        weight: -4,
        predicate: superficial,
        reason: "Thin identity / very short summary (possible wrapper)",
        risk: Some("thin_signal"),
    },
    Rule {
        id: "proprietary_license",
        weight: -3,
        predicate: proprietary_license,
        reason: "Proprietary / closed licensing tone",
        risk: Some("license_lock_in"),
    },
    Rule {
        id: "weak_signals",
        weight: -3,
        predicate: weak_signals,
        reason: "Missing stack fit and category",
        risk: Some("weak_metadata"),
    },
    Rule {
        id: "experimental",
        weight: -3,
        predicate: experimental,
        reason: "Experimental maturity",
        risk: Some("experimental_maturity"),
    },
    Rule {
        id: "hype",
        weight: -2,
        predicate: hype_without_substance,
        reason: "Marketing-heavy wording without depth",
        risk: Some("hype_signal"),
    },
    Rule {
        id: "missing_license",
        weight: -2,
        predicate: confusing_license,
        reason: "License not stated",
        risk: Some("license_unknown"),
    },
];
