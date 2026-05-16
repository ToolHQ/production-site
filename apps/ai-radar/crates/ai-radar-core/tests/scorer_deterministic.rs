//! Deterministic scorer fixtures and invariants (**T-166**).

use ai_radar_core::domain::{Decision, ExtractedItem, Maturity, RiskLevel};
use ai_radar_core::scorer::Scorer;
use chrono::Utc;
use uuid::Uuid;

#[allow(clippy::too_many_arguments)] // test fixture builder
fn base(
    tool_name: Option<&str>,
    summary: &str,
    problem: &str,
    stack_fit: Option<&str>,
    category: Option<&str>,
    license: Option<&str>,
    maturity: Option<Maturity>,
    risk: Option<RiskLevel>,
    self_hosted: Option<bool>,
    saas_only: Option<bool>,
) -> ExtractedItem {
    ExtractedItem {
        id: Uuid::nil(),
        raw_item_id: Uuid::nil(),
        version: 1,
        extractor: "llm-v1".into(),
        tool_name: tool_name.map(String::from),
        category: category.map(String::from),
        summary: Some(summary.into()),
        problem_solved: Some(problem.into()),
        self_hosted,
        saas_only,
        license: license.map(String::from),
        maturity,
        risk_level: risk,
        stack_fit: stack_fit.map(String::from),
        metadata_json: serde_json::json!({}),
        created_at: Utc::now(),
    }
}

#[test]
fn fixture_adopt_high_signal() {
    let summary = "a".repeat(85);
    let problem = "b".repeat(30);
    let stack = "Runs on Kubernetes with Helm chart and operators for day-2.";
    let item = base(
        Some("obs-agent"),
        &summary,
        &problem,
        Some(stack),
        Some("LLM observability"),
        Some("Apache-2.0"),
        Some(Maturity::Stable),
        Some(RiskLevel::Low),
        Some(true),
        Some(false),
    );
    let out = Scorer::v1().score(&item);
    assert_eq!(out.decision, Decision::Adopt);
    assert!(out.points >= 80);
    assert!((0.0..=1.0).contains(&out.normalized_score()));
}

#[test]
fn fixture_test_mid_high() {
    let summary = "c".repeat(79);
    let problem = "d".repeat(26);
    let item = base(
        Some("mid-tool"),
        &summary,
        &problem,
        Some("Rust SDK and REST; reduces infra cost for small teams."),
        Some("devtools"),
        Some("MIT"),
        Some(Maturity::Stable),
        Some(RiskLevel::Low),
        Some(true),
        Some(false),
    );
    let out = Scorer::v1().score(&item);
    assert_eq!(out.decision, Decision::Test);
    assert!((60..80).contains(&out.points));
}

#[test]
fn fixture_monitor_mild() {
    let item = base(
        Some("mild"),
        "short",
        "x",
        None,
        None,
        Some("MIT"),
        Some(Maturity::Stable),
        Some(RiskLevel::Low),
        None,
        None,
    );
    let out = Scorer::v1().score(&item);
    assert_eq!(out.decision, Decision::Monitor);
    assert!((35..60).contains(&out.points));
}

#[test]
fn fixture_ignore_negative_stack() {
    let item = base(
        None,
        "bad",
        "tiny",
        None,
        None,
        None,
        Some(Maturity::Experimental),
        Some(RiskLevel::High),
        None,
        Some(true),
    );
    let out = Scorer::v1().score(&item);
    assert_eq!(out.decision, Decision::Ignore);
    assert!(out.points < 35);
}

#[test]
fn fixture_boundary_monitor_upper_band() {
    // Just below the 60 `test` threshold: a few mild positives without big blocks.
    let item = base(
        Some("edge"),
        "short summary",
        "xx",
        None,
        Some("cat"),
        Some("MIT"),
        Some(Maturity::Stable),
        Some(RiskLevel::Low),
        None,
        None,
    );
    let out = Scorer::v1().score(&item);
    assert_eq!(out.decision, Decision::Monitor);
    assert!((35..60).contains(&out.points));
}

#[test]
fn property_normalized_score_in_unit_interval() {
    let scorer = Scorer::v1();
    for seed in 0u32..800 {
        let item = synth(seed);
        let out = scorer.score(&item);
        let n = out.normalized_score();
        assert!(
            (0.0..=1.0).contains(&n),
            "seed {seed} points {} -> {}",
            out.points,
            n
        );
        // Decision always one of four variants (exhaustive match compile-check).
        let _ = matches!(
            out.decision,
            Decision::Adopt | Decision::Test | Decision::Monitor | Decision::Ignore
        );
    }
}

fn synth(seed: u32) -> ExtractedItem {
    let m = match seed % 5 {
        0 => Some(Maturity::Stable),
        1 => Some(Maturity::Beta),
        2 => Some(Maturity::Experimental),
        3 => Some(Maturity::Deprecated),
        _ => None,
    };
    let r = match seed % 4 {
        0 => Some(RiskLevel::Low),
        1 => Some(RiskLevel::Medium),
        2 => Some(RiskLevel::High),
        _ => None,
    };
    let tool = if seed % 7 == 0 {
        None
    } else {
        Some(format!("tool-{seed}"))
    };
    let summary_len = (seed % 120) as usize;
    let summary = "w".repeat(summary_len.max(1));
    let problem_len = (seed % 40) as usize;
    let problem = "z".repeat(problem_len);
    let self_hosted = match seed % 3 {
        0 => Some(true),
        1 => Some(false),
        _ => None,
    };
    let saas = seed % 11 == 0;
    base(
        tool.as_deref(),
        &summary,
        &problem,
        Some("notes about kubernetes cost savings"),
        Some("category"),
        Some("Apache-2.0"),
        m,
        r,
        self_hosted,
        Some(saas),
    )
}
