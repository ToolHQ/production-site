//! Category comparison engine (**T-168**).

mod criteria;
mod matrix;
mod render;

pub use criteria::{score_criteria, CriteriaScores};
pub use matrix::{ComparisonMatrix, ComparisonRow};
pub use render::render_markdown;

use std::collections::HashSet;

use crate::db::Database;
use crate::domain::{Comparison, ExtractedItem, NewComparison};
use crate::repos::{
    ComparisonRepository, ExtractedItemRepository, PgComparisonRepository,
    PgExtractedItemRepository, PgScoreRepository, ScoreRepository, ScoredItemSort,
};

/// Compare tools within a single `category` (never mixes categories).
#[derive(Debug, Clone, Default)]
pub struct Comparator;

/// Outcome of a compare run.
#[derive(Debug, Clone)]
pub struct CompareResult {
    /// Persisted comparison row.
    pub comparison: Comparison,
    /// Rendered Markdown (duplicate of `comparison.markdown` for convenience).
    pub markdown: String,
}

impl Comparator {
    /// Build a matrix from DB state, persist, and return Markdown.
    ///
    /// # Errors
    ///
    /// Returns when `category` is blank, `top_n` is zero, or repository access fails.
    pub async fn compare(
        &self,
        db: &Database,
        category: &str,
        top_n: usize,
    ) -> anyhow::Result<CompareResult> {
        let category = category.trim();
        if category.is_empty() {
            anyhow::bail!("category must not be empty");
        }
        if top_n == 0 {
            anyhow::bail!("top_n must be >= 1");
        }
        let top_n = top_n.min(50);

        let scores = PgScoreRepository::new(db);
        let extracted = PgExtractedItemRepository::new(db);
        let comparisons = PgComparisonRepository::new(db);

        let summaries = scores
            .list_scored_items(
                top_n as i64 * 3,
                0,
                None,
                Some(category),
                None,
                None,
                None,
                None,
                None,
                None,
                ScoredItemSort::ScoreDesc,
            )
            .await?;

        let mut rows = Vec::new();
        let mut seen_tools = HashSet::new();

        for summary in summaries {
            let cat = summary.category.as_deref().unwrap_or("").trim();
            if !category_eq(category, cat) {
                continue;
            }
            let tool = summary
                .tool_name
                .as_deref()
                .unwrap_or("unknown")
                .trim()
                .to_string();
            if !seen_tools.insert(tool.clone()) {
                continue;
            }

            let item = extracted.get(summary.extracted_item_id).await?;
            validate_same_category(category, &item)?;
            let latest_score = scores.get_latest(summary.extracted_item_id).await?;
            let criteria = score_criteria(&item, &latest_score);

            rows.push(ComparisonRow {
                tool_name: tool,
                extracted_item_id: summary.extracted_item_id,
                overall_score: summary.score,
                decision: summary.decision,
                criteria,
            });

            if rows.len() >= top_n {
                break;
            }
        }

        let matrix = ComparisonMatrix {
            category: category.to_string(),
            top_n,
            rows,
        };

        let markdown = render_markdown(&matrix);
        let matrix_json =
            serde_json::to_value(&matrix).unwrap_or_else(|_| serde_json::json!({}));

        let saved = comparisons
            .insert(&NewComparison {
                category: category.to_string(),
                top_n: i32::try_from(top_n).unwrap_or(50),
                matrix_json,
                markdown: markdown.clone(),
            })
            .await?;

        Ok(CompareResult {
            comparison: saved,
            markdown,
        })
    }
}

fn category_eq(a: &str, b: &str) -> bool {
    a.trim().eq_ignore_ascii_case(b.trim())
}

fn validate_same_category(expected: &str, item: &ExtractedItem) -> anyhow::Result<()> {
    let actual = item.category.as_deref().unwrap_or("").trim();
    if !category_eq(expected, actual) {
        anyhow::bail!(
            "category mismatch: expected '{expected}', item {} has '{actual}'",
            item.id
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    #[test]
    fn rejects_category_mismatch() {
        let item = ExtractedItem {
            category: Some("Other".into()),
            ..minimal_item()
        };
        assert!(validate_same_category("MCP", &item).is_err());
    }

    fn minimal_item() -> ExtractedItem {
        ExtractedItem {
            id: Uuid::new_v4(),
            raw_item_id: Uuid::new_v4(),
            version: 1,
            extractor: "t".into(),
            tool_name: Some("x".into()),
            category: Some("MCP".into()),
            summary: None,
            problem_solved: None,
            self_hosted: None,
            saas_only: None,
            license: None,
            maturity: None,
            risk_level: None,
            stack_fit: None,
            metadata_json: serde_json::json!({}),
            created_at: chrono::Utc::now(),
        }
    }
}
