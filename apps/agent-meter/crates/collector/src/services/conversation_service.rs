use chrono::{DateTime, Utc};
use sqlx::PgPool;

use crate::errors::AppError;
use crate::models::timeline::{ConversationTimeline, TimelineEvent};

#[derive(sqlx::FromRow)]
struct TimelineRow {
    order: i32,
    tool_name: String,
    mcp_server: Option<String>,
    duration_ms: i32,
    estimated_input_tokens: Option<i32>,
    estimated_output_tokens: Option<i32>,
    ok: bool,
    started_at: DateTime<Utc>,
    ended_at: DateTime<Utc>,
}

#[derive(sqlx::FromRow)]
struct SummaryRow {
    user_prompt: Option<String>,
    started_at: DateTime<Utc>,
    ended_at: Option<DateTime<Utc>>,
    total_duration_ms: i64,
    total_tokens_in: Option<i64>,
    total_tokens_out: Option<i64>,
    event_count: i64,
    error_count: i64,
}

pub async fn get_conversation_timeline(
    pool: &PgPool,
    conversation_id: &str,
    limit: Option<i64>,
) -> Result<ConversationTimeline, AppError> {
    // Buscar resumo da conversa
    let summary: Option<SummaryRow> = sqlx::query_as(
        r#"
        SELECT
            user_prompt,
            MIN(started_at) AS started_at,
            MAX(ended_at) AS ended_at,
            SUM(duration_ms)::bigint AS total_duration_ms,
            SUM(estimated_input_tokens)::bigint AS total_tokens_in,
            SUM(estimated_output_tokens)::bigint AS total_tokens_out,
            COUNT(*)::bigint AS event_count,
            COUNT(*) FILTER (WHERE NOT ok)::bigint AS error_count
        FROM agent_tool_calls
        WHERE conversation_id = $1
        GROUP BY user_prompt
        "#,
    )
    .bind(conversation_id)
    .fetch_optional(pool)
    .await?;

    // Se não encontrou, retorna timeline vazio
    let summary = match summary {
        Some(s) => s,
        None => {
            return Ok(ConversationTimeline {
                conversation_id: conversation_id.to_string(),
                title: format!("Conversation {}", conversation_id),
                started_at: chrono::Utc::now(),
                ended_at: chrono::Utc::now(),
                total_duration_ms: 0,
                total_tokens_in: 0,
                total_tokens_out: 0,
                event_count: 0,
                error_count: 0,
                events: vec![],
            });
        }
    };

    // Buscar eventos da conversa
    let events_raw: Vec<TimelineRow> = sqlx::query_as(
        r#"
        SELECT
            ROW_NUMBER() OVER (ORDER BY started_at ASC)::integer AS "order",
            tool_name,
            mcp_server,
            duration_ms,
            estimated_input_tokens,
            estimated_output_tokens,
            ok,
            started_at,
            ended_at
        FROM agent_tool_calls
        WHERE conversation_id = $1
        ORDER BY started_at ASC
        LIMIT $2
        "#,
    )
    .bind(conversation_id)
    .bind(limit.unwrap_or(1000))
    .fetch_all(pool)
    .await?;

    let title = summary
        .user_prompt
        .as_ref()
        .map(|p| {
            let truncated = if p.len() > 50 {
                format!("{}...", &p[..47])
            } else {
                p.clone()
            };
            truncated
        })
        .unwrap_or_else(|| format!("Conversation {}", conversation_id));

    let events = events_raw
        .into_iter()
        .map(|row| TimelineEvent {
            order: row.order as u32,
            tool_name: row.tool_name,
            mcp_server: row.mcp_server,
            duration_ms: row.duration_ms,
            tokens_in: row.estimated_input_tokens,
            tokens_out: row.estimated_output_tokens,
            ok: row.ok,
            started_at: row.started_at,
            ended_at: row.ended_at,
        })
        .collect();

    Ok(ConversationTimeline {
        conversation_id: conversation_id.to_string(),
        title,
        started_at: summary.started_at,
        ended_at: summary.ended_at.unwrap_or(summary.started_at),
        total_duration_ms: summary.total_duration_ms,
        total_tokens_in: summary.total_tokens_in.unwrap_or(0),
        total_tokens_out: summary.total_tokens_out.unwrap_or(0),
        event_count: summary.event_count,
        error_count: summary.error_count,
        events,
    })
}