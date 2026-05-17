//! Markdown renderer for comparison matrices (**T-168**).

use super::matrix::ComparisonMatrix;

/// Render a GitHub-friendly Markdown table.
#[must_use]
pub fn render_markdown(matrix: &ComparisonMatrix) -> String {
    let mut out = String::new();
    out.push_str(&format!(
        "# AI Radar comparison — {}\n\n",
        matrix.category
    ));
    out.push_str(&format!(
        "_Top {} tools by latest score (same category only). Criteria scored 0–3._\n\n",
        matrix.top_n
    ));
    if matrix.rows.is_empty() {
        out.push_str("No scored tools found for this category.\n");
        return out;
    }

    out.push_str("| Tool | Overall | Decision | Self-hosted | K8s | License | Maturity | Activity | Docs |\n");
    out.push_str("|------|---------|----------|-------------|-----|---------|----------|----------|------|\n");

    for row in &matrix.rows {
        let c = &row.criteria;
        out.push_str(&format!(
            "| {} | {:.0}% | {} | {} | {} | {} | {} | {} | {} |\n",
            escape_cell(&row.tool_name),
            row.overall_score * 100.0,
            row.decision.as_str(),
            c.self_hosted,
            c.k8s_friendly,
            c.license_clarity,
            c.maturity,
            c.last_activity,
            c.doc_quality,
        ));
    }
    out
}

fn escape_cell(s: &str) -> String {
    s.replace('|', "\\|")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::comparator::criteria::CriteriaScores;
    use crate::comparator::matrix::ComparisonRow;
    use crate::domain::Decision;

    #[test]
    fn snapshot_markdown_table() {
        let matrix = ComparisonMatrix {
            category: "LLM observability".into(),
            top_n: 2,
            rows: vec![
                ComparisonRow {
                    tool_name: "Coroot".into(),
                    extracted_item_id: uuid::Uuid::nil(),
                    overall_score: 0.82,
                    decision: Decision::Adopt,
                    criteria: CriteriaScores {
                        self_hosted: 3,
                        k8s_friendly: 3,
                        license_clarity: 3,
                        maturity: 2,
                        last_activity: 3,
                        doc_quality: 2,
                    },
                },
                ComparisonRow {
                    tool_name: "Other".into(),
                    extracted_item_id: uuid::Uuid::nil(),
                    overall_score: 0.55,
                    decision: Decision::Test,
                    criteria: CriteriaScores {
                        self_hosted: 1,
                        k8s_friendly: 2,
                        license_clarity: 2,
                        maturity: 1,
                        last_activity: 2,
                        doc_quality: 1,
                    },
                },
            ],
        };
        let md = render_markdown(&matrix);
        assert!(md.contains("LLM observability"));
        assert!(md.contains("| Coroot |"));
        assert!(md.contains("| Other |"));
    }
}
