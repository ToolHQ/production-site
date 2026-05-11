//! Digest generator pipeline (**T-169**).
//!
//! Selects scored items in a time window, renders a Markdown digest and
//! persists it to `ai_radar.digests`.

use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::db::Database;
use crate::domain::{Decision, DigestType, NewDigest};
use crate::repos::{DigestRepository, PgDigestRepository};

/// A digest cadence requested by API/CLI.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DigestKind {
    Daily,
    Weekly,
}

impl DigestKind {
    #[must_use]
    pub fn as_digest_type(self) -> DigestType {
        match self {
            DigestKind::Daily => DigestType::Daily,
            DigestKind::Weekly => DigestType::Weekly,
        }
    }

    #[must_use]
    pub fn window(self, now: DateTime<Utc>) -> (DateTime<Utc>, DateTime<Utc>) {
        match self {
            DigestKind::Daily => (now - Duration::hours(24), now),
            DigestKind::Weekly => (now - Duration::days(7), now),
        }
    }
}

/// Fully-renderable item in the digest.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DigestItem {
    pub raw_item_id: Uuid,
    pub extracted_item_id: Uuid,
    pub score_id: Uuid,
    pub score: f32,
    pub decision: Decision,
    pub tool_name: Option<String>,
    pub category: Option<String>,
    pub url: String,
    pub title: Option<String>,
    pub reasons: Vec<String>,
    pub risks: Vec<String>,
    pub next_step: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DigestData {
    pub digest_type: DigestType,
    pub period_start: DateTime<Utc>,
    pub period_end: DateTime<Utc>,
    pub adopt: Vec<DigestItem>,
    pub test: Vec<DigestItem>,
    pub monitor: Vec<DigestItem>,
    pub ignore: Vec<DigestItem>,
}

#[derive(Debug, Clone, Copy)]
pub struct DigestLimits {
    pub adopt: usize,
    pub test: usize,
    pub monitor: usize,
    pub ignore: usize,
}

impl Default for DigestLimits {
    fn default() -> Self {
        Self {
            adopt: 5,
            test: 10,
            monitor: 5,
            ignore: 5,
        }
    }
}

/// Create and persist a digest for a given window.
///
/// # Errors
///
/// Returns errors from Postgres, validation or rendering.
pub async fn run_digest(db: &Database, kind: DigestKind, limits: DigestLimits) -> anyhow::Result<Uuid> {
    let now = Utc::now();
    let (period_start, period_end) = kind.window(now);
    let data = select(db, kind.as_digest_type(), period_start, period_end, limits).await?;
    let markdown = render_markdown(&data);

    let digests = PgDigestRepository::new(db);
    let row = digests
        .insert(&NewDigest {
            digest_type: data.digest_type,
            period_start: data.period_start,
            period_end: data.period_end,
            markdown_content: markdown,
            metadata_json: Some(serde_json::json!({
                "limits": { "adopt": limits.adopt, "test": limits.test, "monitor": limits.monitor, "ignore": limits.ignore },
                "generator": "digest-v1"
            })),
        })
        .await?;

    Ok(row.id)
}

/// Select scored items in a window and group by decision.
///
/// This is intentionally conservative: it selects by `scores.created_at`
/// (the scoring timestamp), not by raw publish time.
pub async fn select(
    db: &Database,
    digest_type: DigestType,
    period_start: DateTime<Utc>,
    period_end: DateTime<Utc>,
    limits: DigestLimits,
) -> anyhow::Result<DigestData> {
    let sql = "\
        SELECT \
            s.id AS score_id, \
            s.extracted_item_id AS extracted_item_id, \
            s.score AS score, \
            s.decision AS decision, \
            s.next_step AS next_step, \
            s.reasons_json AS reasons_json, \
            s.risks_json AS risks_json, \
            e.raw_item_id AS raw_item_id, \
            e.tool_name AS tool_name, \
            e.category AS category, \
            r.url AS url, \
            r.title AS title \
        FROM ai_radar.scores s \
        JOIN ai_radar.extracted_items e ON e.id = s.extracted_item_id \
        JOIN ai_radar.raw_items r ON r.id = e.raw_item_id \
        WHERE s.created_at >= $1 AND s.created_at <= $2 \
        ORDER BY s.score DESC, s.created_at DESC";

    let rows = sqlx::query(sql)
        .bind(period_start)
        .bind(period_end)
        .fetch_all(&db.pool)
        .await?;

    let mut adopt = Vec::new();
    let mut test = Vec::new();
    let mut monitor = Vec::new();
    let mut ignore = Vec::new();

    for row in rows {
        let decision_raw: String = row.try_get("decision")?;
        let decision = Decision::parse(&decision_raw).map_err(|v| anyhow::anyhow!("unknown decision {v}"))?;

        let reasons_json: serde_json::Value = row.try_get("reasons_json")?;
        let risks_json: serde_json::Value = row.try_get("risks_json")?;

        let item = DigestItem {
            raw_item_id: row.try_get("raw_item_id")?,
            extracted_item_id: row.try_get("extracted_item_id")?,
            score_id: row.try_get("score_id")?,
            score: row.try_get("score")?,
            decision,
            tool_name: row.try_get("tool_name")?,
            category: row.try_get("category")?,
            url: row.try_get("url")?,
            title: row.try_get("title")?,
            reasons: truncate_lines(json_string_list(reasons_json), 3),
            risks: truncate_lines(json_string_list(risks_json), 3),
            next_step: row.try_get("next_step")?,
        };

        match decision {
            Decision::Adopt => adopt.push(item),
            Decision::Test => test.push(item),
            Decision::Monitor => monitor.push(item),
            Decision::Ignore => ignore.push(item),
        }
    }

    // Enforce limits per bucket.
    adopt.truncate(limits.adopt);
    test.truncate(limits.test);
    monitor.truncate(limits.monitor);
    ignore.truncate(limits.ignore);

    Ok(DigestData {
        digest_type,
        period_start,
        period_end,
        adopt,
        test,
        monitor,
        ignore,
    })
}

/// Render a digest as Markdown.
#[must_use]
pub fn render_markdown(data: &DigestData) -> String {
    let mut out = String::new();
    out.push_str(&format!(
        "# AI Radar Digest — {}\n\n",
        data.period_end.format("%Y-%m-%d")
    ));
    out.push_str(&format!(
        "_Period: {} → {} | Type: {}_\n\n",
        data.period_start.format("%Y-%m-%d %H:%M UTC"),
        data.period_end.format("%Y-%m-%d %H:%M UTC"),
        data.digest_type.as_str()
    ));

    render_section(&mut out, "✅ Adotar", &data.adopt);
    render_section(&mut out, "🔥 Testar", &data.test);
    render_section(&mut out, "👀 Monitorar", &data.monitor);
    render_section(&mut out, "❌ Ignorar", &data.ignore);

    out
}

fn render_section(out: &mut String, title: &str, items: &[DigestItem]) {
    out.push_str(&format!("## {title}\n\n"));
    if items.is_empty() {
        out.push_str("_Sem itens nesta janela._\n\n");
        return;
    }

    for (idx, it) in items.iter().enumerate() {
        let name = it
            .tool_name
            .clone()
            .or_else(|| it.title.clone())
            .unwrap_or_else(|| "Untitled".into());
        out.push_str(&format!("### {}. {name}\n\n", idx + 1));
        if let Some(category) = &it.category {
            out.push_str(&format!("- Categoria: {category}\n"));
        }
        out.push_str(&format!("- Score: {:.0}\n", it.score * 100.0));
        out.push_str(&format!("- Link: {}\n", it.url));

        if !it.reasons.is_empty() {
            out.push_str("- Motivos:\n");
            for r in &it.reasons {
                out.push_str(&format!("  - {r}\n"));
            }
        }

        if !it.risks.is_empty() {
            out.push_str("- Riscos:\n");
            for r in &it.risks {
                out.push_str(&format!("  - {r}\n"));
            }
        }

        if let Some(next) = &it.next_step {
            out.push_str(&format!("- Próximo passo: {next}\n"));
        }

        out.push('\n');
    }
}

fn json_string_list(v: serde_json::Value) -> Vec<String> {
    match v {
        serde_json::Value::Array(items) => items
            .into_iter()
            .filter_map(|x| x.as_str().map(|s| s.trim().to_string()))
            .filter(|s| !s.is_empty())
            .collect(),
        _ => Vec::new(),
    }
}

fn truncate_lines(mut items: Vec<String>, max: usize) -> Vec<String> {
    if items.len() > max {
        items.truncate(max);
    }
    items
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn render_is_stable_for_empty_buckets() {
        let data = DigestData {
            digest_type: DigestType::Weekly,
            period_start: Utc.with_ymd_and_hms(2026, 5, 1, 0, 0, 0).unwrap(),
            period_end: Utc.with_ymd_and_hms(2026, 5, 8, 0, 0, 0).unwrap(),
            adopt: vec![],
            test: vec![],
            monitor: vec![],
            ignore: vec![],
        };
        let md = render_markdown(&data);
        assert!(md.contains("# AI Radar Digest — 2026-05-08"));
        assert!(md.contains("## 🔥 Testar"));
        assert!(md.contains("_Sem itens nesta janela._"));
    }

    #[test]
    fn truncate_lines_caps_at_three() {
        let items = vec!["a".into(), "b".into(), "c".into(), "d".into()];
        assert_eq!(truncate_lines(items, 3), vec!["a", "b", "c"]);
    }
}

