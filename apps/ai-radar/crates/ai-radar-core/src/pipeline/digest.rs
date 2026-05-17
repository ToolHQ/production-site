//! Digest generator pipeline (**T-169**).
//!
//! Selects scored items in a time window, renders a Markdown digest and
//! persists it to `ai_radar.digests`.

use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::curation::source_health::SourceHealthTier;
use crate::db::Database;
use crate::domain::{Decision, DigestType, NewDigest};
use crate::repos::{
    DigestRepository, PgDigestRepository, PgSourceHealthRepository, SourceHealthRepository,
};

/// Max highlights per signals section in digest v2.
const SIGNAL_SECTION_LIMIT: i64 = 8;

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

/// Curated signal highlights for digest v2 (**T-241**).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct DigestSignals {
    pub rising: Vec<SignalHighlight>,
    pub adoption: Vec<SignalHighlight>,
    pub sources_alert: Vec<SourceAlertLine>,
    pub feedback_calibration_count: usize,
}

/// One row in trending / adoption sections.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SignalHighlight {
    pub tool_name: String,
    pub url: String,
    pub category: Option<String>,
    pub score: f32,
    pub decision: Decision,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stars: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stars_delta_7d: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub velocity_tier: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stars_tier: Option<String>,
}

/// Noisy or degraded source summary for operators.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SourceAlertLine {
    pub source_name: String,
    pub tier: String,
    pub raw_failed: i64,
    pub raw_skipped: i64,
    pub quality_warn: i64,
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
pub async fn run_digest(
    db: &Database,
    kind: DigestKind,
    limits: DigestLimits,
) -> anyhow::Result<Uuid> {
    let now = Utc::now();
    let (period_start, period_end) = kind.window(now);
    let data = select(db, kind.as_digest_type(), period_start, period_end, limits).await?;
    let signals = select_signals(db, period_start, period_end).await?;
    let markdown = render_markdown(&data, &signals);
    let metadata = build_metadata(&data, limits, &signals);

    let digests = PgDigestRepository::new(db);
    let row = digests
        .insert(&NewDigest {
            digest_type: data.digest_type,
            period_start: data.period_start,
            period_end: data.period_end,
            markdown_content: markdown,
            metadata_json: Some(metadata),
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
        let decision =
            Decision::parse(&decision_raw).map_err(|v| anyhow::anyhow!("unknown decision {v}"))?;

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
            reasons: truncate_lines(
                json_string_list(reasons_json)
                    .into_iter()
                    .map(|r| humanize_reason(&r))
                    .collect(),
                5,
            ),
            risks: truncate_lines(json_string_list(risks_json), 3),
            next_step: display_next_step(row.try_get("next_step")?),
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

/// Load signal highlights for digest v2 sections.
///
/// # Errors
///
/// Returns errors from Postgres or source-health aggregation.
pub async fn select_signals(
    db: &Database,
    period_start: DateTime<Utc>,
    period_end: DateTime<Utc>,
) -> anyhow::Result<DigestSignals> {
    let rising = fetch_velocity_highlights(db, period_start, period_end, SIGNAL_SECTION_LIMIT).await?;
    let adoption =
        fetch_adoption_highlights(db, period_start, period_end, SIGNAL_SECTION_LIMIT).await?;
    let feedback_calibration_count =
        count_feedback_calibrated(db, period_start, period_end).await?;

    let health_repo = PgSourceHealthRepository::new(db);
    let sources_alert: Vec<SourceAlertLine> = health_repo
        .list_all()
        .await?
        .into_iter()
        .filter(|s| {
            matches!(
                s.tier,
                SourceHealthTier::Noisy | SourceHealthTier::Degraded
            )
        })
        .map(|s| SourceAlertLine {
            source_name: s.source_name,
            tier: s.tier.as_str().to_string(),
            raw_failed: s.raw_failed,
            raw_skipped: s.raw_skipped,
            quality_warn: s.quality_warn,
        })
        .collect();

    Ok(DigestSignals {
        rising,
        adoption,
        sources_alert,
        feedback_calibration_count,
    })
}

async fn fetch_velocity_highlights(
    db: &Database,
    period_start: DateTime<Utc>,
    period_end: DateTime<Utc>,
    limit: i64,
) -> anyhow::Result<Vec<SignalHighlight>> {
    let sql = "\
        SELECT \
            s.score, s.decision, \
            e.tool_name, e.category, \
            r.url, r.title, r.tool_key, \
            (e.metadata_json->'adoption'->>'stars')::bigint AS stars, \
            (e.metadata_json->'adoption'->>'stars_delta_7d')::bigint AS stars_delta_7d, \
            e.metadata_json->'adoption'->>'velocity_tier' AS velocity_tier, \
            e.metadata_json->'adoption'->>'stars_tier' AS stars_tier \
        FROM ai_radar.scores s \
        JOIN ai_radar.extracted_items e ON e.id = s.extracted_item_id \
        JOIN ai_radar.raw_items r ON r.id = e.raw_item_id \
        WHERE s.created_at >= $1 AND s.created_at <= $2 \
          AND e.metadata_json->'adoption'->>'velocity_tier' IN ('spike', 'growing') \
        ORDER BY (e.metadata_json->'adoption'->>'stars_delta_7d')::bigint DESC NULLS LAST, \
                 s.score DESC \
        LIMIT $3";
    fetch_signal_rows(db, sql, period_start, period_end, limit).await
}

async fn fetch_adoption_highlights(
    db: &Database,
    period_start: DateTime<Utc>,
    period_end: DateTime<Utc>,
    limit: i64,
) -> anyhow::Result<Vec<SignalHighlight>> {
    let sql = "\
        SELECT \
            s.score, s.decision, \
            e.tool_name, e.category, \
            r.url, r.title, r.tool_key, \
            (e.metadata_json->'adoption'->>'stars')::bigint AS stars, \
            (e.metadata_json->'adoption'->>'stars_delta_7d')::bigint AS stars_delta_7d, \
            e.metadata_json->'adoption'->>'velocity_tier' AS velocity_tier, \
            e.metadata_json->'adoption'->>'stars_tier' AS stars_tier \
        FROM ai_radar.scores s \
        JOIN ai_radar.extracted_items e ON e.id = s.extracted_item_id \
        JOIN ai_radar.raw_items r ON r.id = e.raw_item_id \
        WHERE s.created_at >= $1 AND s.created_at <= $2 \
          AND e.metadata_json->'adoption'->>'stars_tier' IN ('popular', 'viral') \
        ORDER BY (e.metadata_json->'adoption'->>'stars')::bigint DESC NULLS LAST, \
                 s.score DESC \
        LIMIT $3";
    fetch_signal_rows(db, sql, period_start, period_end, limit).await
}

async fn fetch_signal_rows(
    db: &Database,
    sql: &str,
    period_start: DateTime<Utc>,
    period_end: DateTime<Utc>,
    limit: i64,
) -> anyhow::Result<Vec<SignalHighlight>> {
    let rows = sqlx::query(sql)
        .bind(period_start)
        .bind(period_end)
        .bind(limit)
        .fetch_all(&db.pool)
        .await?;

    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        let decision_raw: String = row.try_get("decision")?;
        let decision =
            Decision::parse(&decision_raw).map_err(|v| anyhow::anyhow!("unknown decision {v}"))?;
        let tool_name: Option<String> = row.try_get("tool_name")?;
        let title: Option<String> = row.try_get("title")?;
        let name = tool_name
            .or(title)
            .unwrap_or_else(|| "Sem título".into());
        out.push(SignalHighlight {
            tool_name: name,
            url: row.try_get("url")?,
            category: row.try_get("category")?,
            score: row.try_get("score")?,
            decision,
            tool_key: row.try_get("tool_key")?,
            stars: row.try_get("stars")?,
            stars_delta_7d: row.try_get("stars_delta_7d")?,
            velocity_tier: row.try_get("velocity_tier")?,
            stars_tier: row.try_get("stars_tier")?,
        });
    }
    Ok(out)
}

async fn count_feedback_calibrated(
    db: &Database,
    period_start: DateTime<Utc>,
    period_end: DateTime<Utc>,
) -> anyhow::Result<usize> {
    let row: (i64,) = sqlx::query_as(
        "\
        SELECT COUNT(*)::bigint \
        FROM ai_radar.scores \
        WHERE created_at >= $1 AND created_at <= $2 \
          AND COALESCE(metadata_json->>'feedback_calibration', 'false') = 'true'",
    )
    .bind(period_start)
    .bind(period_end)
    .fetch_one(&db.pool)
    .await?;
    Ok(row.0 as usize)
}

/// JSON metadata persisted with each digest (console reads `buckets`).
#[must_use]
pub fn build_metadata(
    data: &DigestData,
    limits: DigestLimits,
    signals: &DigestSignals,
) -> serde_json::Value {
    let total = data.adopt.len() + data.test.len() + data.monitor.len() + data.ignore.len();
    let rising_tool_keys: Vec<&str> = signals
        .rising
        .iter()
        .filter_map(|h| h.tool_key.as_deref())
        .collect();
    let noisy_source_ids: Vec<String> = signals
        .sources_alert
        .iter()
        .map(|s| s.source_name.clone())
        .collect();
    serde_json::json!({
        "generator": "digest-v2",
        "limits": {
            "adopt": limits.adopt,
            "test": limits.test,
            "monitor": limits.monitor,
            "ignore": limits.ignore,
        },
        "summary": {
            "total": total,
            "adopt": data.adopt.len(),
            "test": data.test.len(),
            "monitor": data.monitor.len(),
            "ignore": data.ignore.len(),
        },
        "signals_summary": {
            "rising": signals.rising.len(),
            "adoption": signals.adoption.len(),
            "sources_alert": signals.sources_alert.len(),
            "feedback_calibration_count": signals.feedback_calibration_count,
        },
        "rising_tool_keys": rising_tool_keys,
        "noisy_source_ids": noisy_source_ids,
        "rising_stars": signals.rising,
        "trending_adoption": signals.adoption,
        "sources_alert": signals.sources_alert,
        "buckets": {
            "adopt": data.adopt,
            "test": data.test,
            "monitor": data.monitor,
            "ignore": data.ignore,
        },
    })
}

/// Render a digest as Markdown (export, e-mail, fallback UI).
#[must_use]
pub fn render_markdown(data: &DigestData, signals: &DigestSignals) -> String {
    let mut out = String::new();
    out.push_str(&format!(
        "# AI Radar Digest — {}\n\n",
        data.period_end.format("%Y-%m-%d")
    ));
    out.push_str(&format!(
        "**Período:** {} → {} · **Tipo:** {}\n\n",
        data.period_start.format("%Y-%m-%d %H:%M UTC"),
        data.period_end.format("%Y-%m-%d %H:%M UTC"),
        digest_type_label_pt(data.digest_type)
    ));
    render_executive_summary(&mut out, data);
    render_signals_sections(&mut out, signals);

    render_section(&mut out, "✅ Adotar", &data.adopt);
    render_section(&mut out, "🔥 Testar", &data.test);
    render_section(&mut out, "👀 Monitorar", &data.monitor);
    render_section(&mut out, "❌ Ignorar", &data.ignore);

    out
}

fn digest_type_label_pt(t: DigestType) -> &'static str {
    match t {
        DigestType::Daily => "diário",
        DigestType::Weekly => "semanal",
        DigestType::Monthly => "mensal",
        DigestType::Custom => "personalizado",
    }
}

fn render_signals_sections(out: &mut String, signals: &DigestSignals) {
    render_signal_highlights(out, "## Em ascensão", &signals.rising, true);
    render_signal_highlights(out, "## Destaques de adoção", &signals.adoption, false);
    render_sources_alert(out, &signals.sources_alert);
    if signals.feedback_calibration_count > 0 {
        out.push_str(&format!(
            "## Calibração por feedback\n\n\
             **{}** score(s) ajustado(s) com base em labels humanos nesta janela.\n\n",
            signals.feedback_calibration_count
        ));
    }
}

fn render_signal_highlights(
    out: &mut String,
    title: &str,
    items: &[SignalHighlight],
    show_velocity: bool,
) {
    out.push_str(&format!("{title}\n\n"));
    if items.is_empty() {
        out.push_str("_Nenhum destaque nesta janela._\n\n");
        return;
    }
    for (idx, it) in items.iter().enumerate() {
        out.push_str(&format!(
            "{}. **{}** — score {:.0}/100 ({})",
            idx + 1,
            it.tool_name,
            it.score * 100.0,
            decision_label_pt(it.decision)
        ));
        if let Some(cat) = &it.category {
            out.push_str(&format!(" · {cat}"));
        }
        out.push('\n');
        if let Some(stars) = it.stars {
            out.push_str(&format!("   - ⭐ {stars} stars"));
            if let Some(delta) = it.stars_delta_7d {
                out.push_str(&format!(" (Δ7d {delta:+})"));
            }
            out.push('\n');
        }
        if show_velocity {
            if let Some(v) = &it.velocity_tier {
                out.push_str(&format!(
                    "   - Tendência: {}\n",
                    velocity_label_pt(v)
                ));
            }
        } else if let Some(t) = &it.stars_tier {
            out.push_str(&format!(
                "   - Faixa: {}\n",
                stars_tier_label_pt(t)
            ));
        }
        out.push_str(&format!("   - {}\n", it.url));
    }
    out.push('\n');
}

fn render_sources_alert(out: &mut String, alerts: &[SourceAlertLine]) {
    out.push_str("## Fontes (saúde)\n\n");
    if alerts.is_empty() {
        out.push_str("_Todas as fontes monitoradas estão saudáveis ou sem amostra suficiente._\n\n");
        return;
    }
    out.push_str("⚠️ Fontes com ruído ou degradação — revisar antes de confiar no ranking:\n\n");
    for a in alerts {
        out.push_str(&format!(
            "- **{}** ({}) — falhas collect: {}, skips: {}, avisos qualidade: {}\n",
            a.source_name,
            source_health_label_pt(&a.tier),
            a.raw_failed,
            a.raw_skipped,
            a.quality_warn
        ));
    }
    out.push('\n');
}

fn velocity_label_pt(tier: &str) -> &'static str {
    match tier {
        "spike" => "pico (spike)",
        "growing" => "em crescimento",
        "flat" => "estável",
        "declining" => "em queda",
        _ => "desconhecida",
    }
}

fn stars_tier_label_pt(tier: &str) -> String {
    match tier {
        "viral" => "viral (10k+ stars)".into(),
        "popular" => "popular (1k+ stars)".into(),
        "growing" => "crescendo".into(),
        "niche" => "nicho".into(),
        other => other.to_string(),
    }
}

fn source_health_label_pt(tier: &str) -> String {
    match tier {
        "noisy" => "ruidosa".into(),
        "degraded" => "degradada".into(),
        "healthy" => "saudável".into(),
        other => other.to_string(),
    }
}

fn render_executive_summary(out: &mut String, data: &DigestData) {
    let total = data.adopt.len() + data.test.len() + data.monitor.len() + data.ignore.len();
    out.push_str("## Resumo executivo\n\n");
    if total == 0 {
        out.push_str("Nenhum item scored nesta janela.\n\n");
        return;
    }
    out.push_str(&format!(
        "- **{total}** itens no relatório\n\
         - **{}** adotar · **{}** testar · **{}** monitorar · **{}** ignorar\n\n",
        data.adopt.len(),
        data.test.len(),
        data.monitor.len(),
        data.ignore.len()
    ));
}

fn render_section(out: &mut String, title: &str, items: &[DigestItem]) {
    out.push_str(&format!("## {title}\n\n"));
    if items.is_empty() {
        out.push_str("_Sem itens nesta janela._\n\n");
        return;
    }

    for (idx, it) in items.iter().enumerate() {
        render_item(out, idx + 1, it);
    }
}

fn render_item(out: &mut String, index: usize, it: &DigestItem) {
    let name = item_display_name(it);
    out.push_str(&format!("### {index}. {name}\n\n"));
    if let Some(category) = &it.category {
        out.push_str(&format!("- **Categoria:** {category}\n"));
    }
    out.push_str(&format!(
        "- **Score:** {:.0}/100 · **Decisão:** {}\n",
        it.score * 100.0,
        decision_label_pt(it.decision)
    ));
    out.push_str(&format!("- **Fonte:** {}\n", it.url));

    if !it.reasons.is_empty() {
        out.push_str("- **Motivos:**\n");
        for r in &it.reasons {
            out.push_str(&format!("  - {r}\n"));
        }
    }

    if !it.risks.is_empty() {
        out.push_str("- **Riscos:**\n");
        for r in &it.risks {
            out.push_str(&format!("  - {r}\n"));
        }
    }

    if let Some(next) = &it.next_step {
        out.push_str(&format!("- **Próximo passo:** {next}\n"));
    }

    out.push('\n');
}

fn item_display_name(it: &DigestItem) -> String {
    it.tool_name
        .clone()
        .or_else(|| it.title.clone())
        .unwrap_or_else(|| "Sem título".into())
}

fn decision_label_pt(d: Decision) -> &'static str {
    match d {
        Decision::Adopt => "adotar",
        Decision::Test => "testar",
        Decision::Monitor => "monitorar",
        Decision::Ignore => "ignorar",
    }
}

/// Scorer default follow-ups — omitted in digest when unchanged.
const GENERIC_NEXT_STEPS: &[&str] = &[
    "Promote to team standard; track adoption metrics and owner.",
    "Run a time-boxed spike in a sandbox cluster before wide rollout.",
    "No immediate action — revisit next digest cycle unless signals change.",
    "Archive; do not spend further review time unless new evidence appears.",
];

fn is_generic_next_step(s: &str) -> bool {
    GENERIC_NEXT_STEPS.contains(&s.trim())
}

fn display_next_step(s: Option<String>) -> Option<String> {
    s.filter(|x| !is_generic_next_step(x))
}

/// Turn `+2 [self_hosted] Self-hostable…` into a short pt-BR line for operators.
#[must_use]
pub fn humanize_reason(raw: &str) -> String {
    let trimmed = raw.trim();
    let (weight, rest) = parse_reason_weight(trimmed);
    let (rule_id, tail) = parse_reason_bracket(rest);

    let label = rule_id
        .map(rule_label_pt)
        .unwrap_or_else(|| tail.clone().unwrap_or_default());

    if let Some(w) = weight {
        if label.is_empty() {
            return format!("{w:+}");
        }
        return format!("{w:+} {label}");
    }
    if label.is_empty() {
        return trimmed.to_string();
    }
    label
}

fn parse_reason_weight(s: &str) -> (Option<i32>, &str) {
    let bytes = s.as_bytes();
    if bytes.is_empty() || (bytes[0] != b'+' && bytes[0] != b'-') {
        return (None, s);
    }
    let sign = if bytes[0] == b'-' { -1 } else { 1 };
    let mut i = 1;
    while i < bytes.len() && bytes[i].is_ascii_digit() {
        i += 1;
    }
    if i == 1 {
        return (None, s);
    }
    let n: i32 = s[1..i].parse().unwrap_or(0);
    (Some(sign * n), s[i..].trim_start())
}

fn parse_reason_bracket(s: &str) -> (Option<&str>, Option<String>) {
    let s = s.trim_start();
    if !s.starts_with('[') {
        return (None, Some(s.to_string()));
    }
    let Some(end) = s.find(']') else {
        return (None, Some(s.to_string()));
    };
    let id = &s[1..end];
    let tail = s[end + 1..].trim();
    let tail = tail
        .strip_prefix('—')
        .or_else(|| tail.strip_prefix('-'))
        .map(str::trim)
        .filter(|t| !t.is_empty())
        .map(str::to_string);
    (Some(id), tail)
}

fn rule_label_pt(id: &str) -> String {
    RULE_LABELS_PT
        .iter()
        .find(|(k, _)| *k == id)
        .map(|(_, v)| (*v).to_string())
        .unwrap_or_else(|| id.replace('_', " "))
}

static RULE_LABELS_PT: &[(&str, &str)] = &[
    ("problem_filled", "Problema e caso de uso claros"),
    ("self_hosted", "Compatível com self-host no cluster"),
    ("k8s_fit", "Encaixa em Kubernetes / plataforma"),
    ("structured_identity", "Nome e categoria estruturados"),
    ("rich_summary", "Resumo rico (sinal forte)"),
    ("category_present", "Categoria identificada"),
    ("cost_productivity", "Ângulo de custo / produtividade"),
    ("permissive_license", "Licença permissiva conhecida"),
    ("mature", "Maturidade estável"),
    ("low_risk", "Risco operacional baixo"),
    ("deep_stack_notes", "Notas de stack / ops detalhadas"),
    ("saas_lockin", "Apenas SaaS (sem self-host)"),
    ("high_risk", "Risco operacional alto"),
    ("deprecated", "Projeto obsoleto / deprecated"),
    ("superficial", "Identidade fraca / resumo curto"),
    ("proprietary_license", "Licença proprietária / fechada"),
    ("weak_signals", "Metadados fracos (stack/categoria)"),
    ("experimental", "Maturidade experimental"),
    ("hype", "Texto promocional sem profundidade"),
    ("missing_license", "Licença não informada"),
    ("velocity_spike", "Popularidade em forte alta (7d)"),
    ("velocity_stale", "Popularidade estagnada ou em queda"),
    ("source_noisy", "Fonte com alto ruído / falhas"),
    ("source_degraded", "Fonte degradada (erros de collect)"),
];

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
        let signals = DigestSignals::default();
        let md = render_markdown(&data, &signals);
        assert!(md.contains("# AI Radar Digest — 2026-05-08"));
        assert!(md.contains("## Em ascensão"));
        assert!(md.contains("## 🔥 Testar"));
        assert!(md.contains("_Sem itens nesta janela._"));
    }

    #[test]
    fn render_signals_sections_with_highlights() {
        let data = DigestData {
            digest_type: DigestType::Weekly,
            period_start: Utc.with_ymd_and_hms(2026, 5, 1, 0, 0, 0).unwrap(),
            period_end: Utc.with_ymd_and_hms(2026, 5, 8, 0, 0, 0).unwrap(),
            adopt: vec![],
            test: vec![],
            monitor: vec![],
            ignore: vec![],
        };
        let signals = DigestSignals {
            rising: vec![SignalHighlight {
                tool_name: "CoolTool".into(),
                url: "https://github.com/x/cool".into(),
                category: Some("agents".into()),
                score: 0.82,
                decision: Decision::Test,
                tool_key: Some("github:x/cool".into()),
                stars: Some(12_000),
                stars_delta_7d: Some(500),
                velocity_tier: Some("spike".into()),
                stars_tier: Some("viral".into()),
            }],
            adoption: vec![],
            sources_alert: vec![SourceAlertLine {
                source_name: "lobsters-ai".into(),
                tier: "noisy".into(),
                raw_failed: 2,
                raw_skipped: 40,
                quality_warn: 5,
            }],
            feedback_calibration_count: 3,
        };
        let md = render_markdown(&data, &signals);
        assert!(md.contains("CoolTool"));
        assert!(md.contains("pico (spike)"));
        assert!(md.contains("lobsters-ai"));
        assert!(md.contains("**3** score(s) ajustado(s)"));

        let meta = build_metadata(&data, DigestLimits::default(), &signals);
        assert_eq!(meta["generator"], "digest-v2");
        assert_eq!(meta["rising_tool_keys"][0], "github:x/cool");
        assert_eq!(meta["signals_summary"]["feedback_calibration_count"], 3);
    }

    #[test]
    fn truncate_lines_caps_at_three() {
        let items = vec!["a".into(), "b".into(), "c".into(), "d".into()];
        assert_eq!(truncate_lines(items, 3), vec!["a", "b", "c"]);
    }

    #[test]
    fn humanize_reason_strips_rule_tag() {
        let h = humanize_reason(
            "+2 [self_hosted] Self-hostable (fits constrained cluster policy)",
        );
        assert!(h.contains("self-host"));
        assert!(!h.contains("[self_hosted]"));
    }

    #[test]
    fn generic_next_step_hidden() {
        assert!(display_next_step(Some(
            "Run a time-boxed spike in a sandbox cluster before wide rollout.".into()
        ))
        .is_none());
        assert!(display_next_step(Some("Spike em staging esta semana".into())).is_some());
    }
}
