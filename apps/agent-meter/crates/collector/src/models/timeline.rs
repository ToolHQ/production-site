use chrono::{DateTime, Utc};
use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct TimelineEvent {
    pub order: u32,
    pub tool_name: String,
    pub mcp_server: Option<String>,
    pub duration_ms: i32,
    pub tokens_in: Option<i32>,
    pub tokens_out: Option<i32>,
    pub ok: bool,
    pub started_at: DateTime<Utc>,
    pub ended_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
pub struct ConversationTimeline {
    pub conversation_id: String,
    pub title: String,
    pub started_at: DateTime<Utc>,
    pub ended_at: DateTime<Utc>,
    pub total_duration_ms: i64,
    pub total_tokens_in: i64,
    pub total_tokens_out: i64,
    pub event_count: i64,
    pub error_count: i64,
    pub events: Vec<TimelineEvent>,
}