//! LLM scorer + merge policy tests (**T-167**).

use std::sync::Arc;

use ai_radar_core::domain::{Decision, ExtractedItem, Maturity, RiskLevel};
use ai_radar_core::llm::{CompletionRequest, CompletionResponse, LlmError, LlmProvider, MockLlmProvider};
use ai_radar_core::scorer::{
    merged_to_new_score, LlmScorer, MergePolicy, MergedScoreResult, Scorer,
};

fn sample_item() -> ExtractedItem {
    ExtractedItem {
        id: uuid::Uuid::new_v4(),
        raw_item_id: uuid::Uuid::new_v4(),
        version: 1,
        extractor: "llm-v2".into(),
        tool_name: Some("DemoTool".into()),
        category: Some("MCP".into()),
        summary: Some("A demo MCP server".into()),
        problem_solved: Some("Connects agents to APIs".into()),
        self_hosted: Some(true),
        saas_only: Some(false),
        license: Some("MIT".into()),
        maturity: Some(Maturity::Beta),
        risk_level: Some(RiskLevel::Low),
        stack_fit: Some("k8s-friendly".into()),
        metadata_json: serde_json::json!({}),
        created_at: chrono::Utc::now(),
    }
}

#[tokio::test]
async fn llm_scorer_parses_json_opinion() {
    let json = r#"{"score":72,"reasons":["clear MIT license"],"risks":["young project"]}"#;
    let llm: Arc<dyn LlmProvider> = Arc::new(MockLlmProvider::fixed(json));
    let (opinion, _) = LlmScorer.evaluate(llm.as_ref(), &sample_item())
        .await
        .expect("evaluate");
    assert_eq!(opinion.points, 72);
    assert_eq!(opinion.reasons.len(), 1);
    assert_eq!(opinion.risks, vec!["young project".to_string()]);
}

#[tokio::test]
async fn weighted_merge_persists_metadata() {
    let det = Scorer::v1().score(&sample_item());
    let det_points = det.points;
    let llm = ai_radar_core::scorer::LlmScoreOpinion {
        points: 50,
        reasons: vec!["neutral".into()],
        risks: vec![],
    };
    let policy = MergePolicy::Weighted {
        deterministic: 0.7,
        llm: 0.3,
    };
    let merged = MergedScoreResult::merge(det, Some(llm), policy);
    let row = merged_to_new_score(&merged, uuid::Uuid::new_v4(), Some("mock/model"), Some(0.0));
    assert_eq!(row.scoring_version, "merged-v1");
    let meta = row.metadata_json.as_ref().expect("meta");
    assert_eq!(
        meta.get("deterministic_score").and_then(|v| v.as_i64()),
        Some(i64::from(det_points))
    );
    assert_eq!(meta.get("llm_score").and_then(|v| v.as_i64()), Some(50));
    assert!(meta.get("merge_policy").is_some());
}

#[test]
fn deterministic_only_matches_t166_thresholds() {
    let det = Scorer::v1().score(&sample_item());
    let merged = MergedScoreResult::merge(det.clone(), None, MergePolicy::DeterministicOnly);
    assert_eq!(merged.final_points, det.points);
    assert_eq!(merged.decision, det.decision);
}

struct HighScoreLlm;

#[async_trait::async_trait]
impl LlmProvider for HighScoreLlm {
    async fn complete(&self, _req: CompletionRequest) -> Result<CompletionResponse, LlmError> {
        Ok(CompletionResponse {
            content: r#"{"score":95,"reasons":["excellent"],"risks":[]}"#.into(),
            prompt_tokens: Some(1),
            completion_tokens: Some(1),
            model: "mock/high".into(),
            latency_ms: 1,
        })
    }
}

#[tokio::test]
async fn weighted_merge_can_lift_decision() {
    let item = ExtractedItem {
        risk_level: Some(RiskLevel::High),
        maturity: Some(Maturity::Experimental),
        saas_only: Some(true),
        ..sample_item()
    };
    let det = Scorer::v1().score(&item);
    assert!(det.points < 80);
    let llm: Arc<dyn LlmProvider> = Arc::new(HighScoreLlm);
    let (opinion, _) = LlmScorer.evaluate(llm.as_ref(), &item).await.expect("llm");
    let merged = MergedScoreResult::merge(
        det,
        Some(opinion),
        MergePolicy::Weighted {
            deterministic: 0.5,
            llm: 0.5,
        },
    );
    assert!(merged.final_points >= 60);
    assert_ne!(merged.decision, Decision::Ignore);
}
