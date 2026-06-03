//! Fleet Copilot — auth + proxy to fleet-ops-gateway (T-322).

use axum::{
    extract::{Query, State},
    http::{header, HeaderMap, StatusCode},
    response::{
        sse::{Event, KeepAlive, Sse},
        IntoResponse, Response,
    },
    Json,
};
use futures_util::{FutureExt, StreamExt};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    borrow::Cow,
    collections::HashMap,
    convert::Infallible,
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::sync::Mutex;
use tokio_postgres::NoTls;
use tokio_stream::wrappers::ReceiverStream;

const COOKIE_NAME: &str = "fleet-copilot-session";
const MAX_BODY_MSG: usize = 4000;
const RATE_WINDOW: Duration = Duration::from_secs(60);
const RATE_MAX: usize = 10;
const MAX_HISTORY_TURNS: usize = 8;
const MAX_TURN_CHARS: usize = 600;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ChatIntent {
    MetaCapabilities,
    FleetResources,
    HostHealth,
    K8sStatus,
    SshAudit,
    FleetCompare,
    OciNodeQuery,
    /// Pergunta livre — contexto coletado para o LLM, sem template read-only.
    General,
}

struct AuditEvent<'a> {
    client_ip: Option<&'a str>,
    message: &'a str,
    preset: &'a str,
    intent: &'a str,
    endpoints: &'a [String],
    latency_ms: u64,
    model: &'a str,
    status: &'a str,
}

#[derive(Clone)]
pub struct FleetCopilotState {
    login_key: String,
    session_token: String,
    gateway_url: String,
    gateway_token: String,
    ollama_model: String,
    client: Client,
    rate: Arc<Mutex<HashMap<String, Vec<Instant>>>>,
    audit_db_url: Option<String>,
    audit: Arc<Mutex<Option<Arc<tokio_postgres::Client>>>>,
    audit_schema_ready: Arc<Mutex<bool>>,
}

#[derive(Deserialize)]
pub struct LoginQuery {
    pub key: Option<String>,
}

#[derive(Serialize)]
pub struct SessionResponse {
    pub authenticated: bool,
    pub enabled: bool,
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct ChatTurn {
    pub role: String,
    pub content: String,
}

#[derive(Deserialize)]
pub struct ChatRequest {
    pub message: String,
    #[serde(default)]
    pub preset: Option<String>,
    #[serde(default)]
    pub history: Vec<ChatTurn>,
}

#[derive(Serialize)]
pub struct ChatResponse {
    pub reply: String,
    pub model: String,
    pub sources: Vec<String>,
    pub latency_ms: u64,
}

#[derive(Serialize)]
pub struct StatusResponse {
    pub authenticated: bool,
    pub enabled: bool,
    pub gateway_reachable: bool,
    pub ollama_model: String,
    pub inference_mode: &'static str,
    pub structured_models: Vec<&'static str>,
    pub rate_limit_max: usize,
    pub rate_limit_remaining: usize,
    pub thread_context: bool,
}

impl FleetCopilotState {
    pub fn from_env() -> Option<Arc<Self>> {
        let enabled = std::env::var("FLEET_COPILOT_ENABLED")
            .ok()
            .is_some_and(|v| v == "1" || v.eq_ignore_ascii_case("true"));
        if !enabled {
            return None;
        }

        let login_key = std::env::var("FLEET_COPILOT_LOGIN_KEY").ok()?;
        let session_secret = std::env::var("FLEET_COPILOT_SESSION_SECRET").ok()?;
        let gateway_url = std::env::var("FLEET_COPILOT_GATEWAY_URL")
            .unwrap_or_else(|_| "http://104.225.218.78:18443".into());
        let gateway_token = std::env::var("FLEET_COPILOT_GATEWAY_TOKEN").ok()?;
        let ollama_model =
            std::env::var("FLEET_COPILOT_OLLAMA_MODEL").unwrap_or_else(|_| "gemma3:4b".into());
        let audit_db_url = std::env::var("FLEET_COPILOT_AUDIT_DATABASE_URL")
            .ok()
            .or_else(|| std::env::var("DATABASE_URL").ok());

        let mut hasher = Sha256::new();
        hasher.update(session_secret.as_bytes());
        hasher.update(b":fleet-copilot-v1");
        let session_token: String = hasher
            .finalize()
            .iter()
            .map(|b| format!("{:02x}", b))
            .collect();

        let client = Client::builder()
            .timeout(Duration::from_secs(200))
            .build()
            .ok()?;

        Some(Arc::new(Self {
            login_key,
            session_token,
            gateway_url,
            gateway_token,
            ollama_model,
            client,
            rate: Arc::new(Mutex::new(HashMap::new())),
            audit_db_url,
            audit: Arc::new(Mutex::new(None)),
            audit_schema_ready: Arc::new(Mutex::new(false)),
        }))
    }

    async fn gateway_reachable(&self) -> bool {
        let url = format!("{}/health", self.gateway_url.trim_end_matches('/'));
        self.client
            .get(&url)
            .header(header::AUTHORIZATION, self.auth_header())
            .send()
            .await
            .map(|r| r.status().is_success())
            .unwrap_or(false)
    }

    async fn audit_client(&self) -> Option<Arc<tokio_postgres::Client>> {
        let db_url = self.audit_db_url.as_deref()?;

        if let Some(existing) = self.audit.lock().await.as_ref().cloned() {
            return Some(existing);
        }

        let (client, connection) = tokio_postgres::connect(db_url, NoTls).await.ok()?;
        tokio::spawn(async move {
            let _ = connection.await;
        });

        let client = Arc::new(client);
        *self.audit.lock().await = Some(client.clone());
        Some(client)
    }

    async fn ensure_audit_schema(&self, client: &tokio_postgres::Client) -> bool {
        {
            let ready = self.audit_schema_ready.lock().await;
            if *ready {
                return true;
            }
        }

        let schema_sql = r#"
CREATE SCHEMA IF NOT EXISTS fleet_copilot;
CREATE TABLE IF NOT EXISTS fleet_copilot.audit_events (
  id BIGSERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  client_ip INET,
  prompt_sha256 CHAR(64) NOT NULL,
  preset TEXT,
  intent TEXT,
  endpoints TEXT[] NOT NULL,
  latency_ms INT,
  model TEXT,
  status TEXT NOT NULL
);
"#;
        if client.batch_execute(schema_sql).await.is_err() {
            return false;
        }

        *self.audit_schema_ready.lock().await = true;
        true
    }

    fn prompt_sha256(message: &str, preset: &str) -> String {
        let mut hasher = Sha256::new();
        hasher.update(message.as_bytes());
        hasher.update(b":");
        hasher.update(preset.as_bytes());
        hasher
            .finalize()
            .iter()
            .map(|b| format!("{:02x}", b))
            .collect()
    }

    async fn audit_event(&self, event: AuditEvent<'_>) {
        let Some(client) = self.audit_client().await else {
            return;
        };
        if !self.ensure_audit_schema(client.as_ref()).await {
            return;
        }

        let prompt_sha = Self::prompt_sha256(event.message, event.preset);
        let endpoints: Vec<&str> = event.endpoints.iter().map(|s| s.as_str()).collect();
        let latency_i32 = i32::try_from(event.latency_ms.min(i32::MAX as u64)).unwrap_or(i32::MAX);

        let _ = client
            .execute(
                "INSERT INTO fleet_copilot.audit_events \
                 (client_ip, prompt_sha256, preset, intent, endpoints, latency_ms, model, status) \
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
                &[
                    &event.client_ip,
                    &prompt_sha,
                    &event.preset,
                    &event.intent,
                    &endpoints,
                    &latency_i32,
                    &event.model,
                    &event.status,
                ],
            )
            .await;
    }

    fn session_cookie_value(&self) -> String {
        self.session_token.clone()
    }

    pub fn check_auth(&self, headers: &HeaderMap) -> bool {
        self.is_authenticated(headers)
    }

    fn is_authenticated(&self, headers: &HeaderMap) -> bool {
        let Some(raw) = headers.get(header::COOKIE) else {
            return false;
        };
        let Ok(cookies) = raw.to_str() else {
            return false;
        };
        cookies.split(';').any(|part| {
            let part = part.trim();
            part.strip_prefix(COOKIE_NAME)
                .is_some_and(|v| v.trim_start_matches('=') == self.session_token)
        })
    }

    async fn check_rate(&self, key: &str) -> bool {
        let mut map = self.rate.lock().await;
        let now = Instant::now();
        let entries = map.entry(key.to_string()).or_default();
        entries.retain(|t| now.duration_since(*t) < RATE_WINDOW);
        if entries.len() >= RATE_MAX {
            return false;
        }
        entries.push(now);
        true
    }

    async fn rate_remaining(&self, key: &str) -> usize {
        let map = self.rate.lock().await;
        let now = Instant::now();
        let used = map
            .get(key)
            .map(|entries| {
                entries
                    .iter()
                    .filter(|t| now.duration_since(**t) < RATE_WINDOW)
                    .count()
            })
            .unwrap_or(0);
        RATE_MAX.saturating_sub(used)
    }

    fn normalize_history(history: Vec<ChatTurn>) -> Vec<ChatTurn> {
        history
            .into_iter()
            .filter_map(|turn| {
                let role = turn.role.to_lowercase();
                if role != "user" && role != "assistant" {
                    return None;
                }
                let content = turn.content.trim();
                if content.is_empty() {
                    return None;
                }
                let clipped = if content.len() > MAX_TURN_CHARS {
                    format!("{}…", &content[..MAX_TURN_CHARS])
                } else {
                    content.to_string()
                };
                Some(ChatTurn {
                    role,
                    content: clipped,
                })
            })
            .collect::<Vec<_>>()
            .into_iter()
            .rev()
            .take(MAX_HISTORY_TURNS)
            .collect::<Vec<_>>()
            .into_iter()
            .rev()
            .collect()
    }

    fn last_user_content(history: &[ChatTurn]) -> Option<String> {
        history
            .iter()
            .rev()
            .find(|t| t.role == "user")
            .map(|t| t.content.clone())
    }

    fn routing_message<'a>(message: &'a str, history: &[ChatTurn]) -> Cow<'a, str> {
        if Self::is_conversational_clarification(message) {
            if let Some(prev) = Self::last_user_content(history) {
                return Cow::Owned(prev);
            }
        }
        Cow::Borrowed(message)
    }

    fn llm_message(message: &str, history: &[ChatTurn]) -> String {
        if Self::is_conversational_clarification(message) {
            if let Some(prev) = Self::last_user_content(history) {
                return format!(
                    "{message}\n\n(Reavaliando com base na pergunta anterior: \"{prev}\")"
                );
            }
        }
        message.to_string()
    }

    fn attach_conversation_history(context: &mut Value, history: &[ChatTurn]) {
        if history.is_empty() {
            return;
        }
        context["conversation_history"] = json!(history);
    }

    fn should_clarification_fast_path(message: &str, history: &[ChatTurn]) -> bool {
        Self::is_conversational_clarification(message) && history.is_empty()
    }

    fn should_skip_structured(message: &str, history: &[ChatTurn]) -> bool {
        Self::is_conversational_clarification(message) && !history.is_empty()
    }

    fn auth_header(&self) -> String {
        format!("Bearer {}", self.gateway_token)
    }

    async fn fetch_ops(&self, path: &str) -> Result<Value, String> {
        let url = format!(
            "{}/{}",
            self.gateway_url.trim_end_matches('/'),
            path.trim_start_matches('/')
        );
        let resp = self
            .client
            .get(&url)
            .header(header::AUTHORIZATION, self.auth_header())
            .send()
            .await
            .map_err(|e| e.to_string())?;
        if !resp.status().is_success() {
            return Err(format!("gateway {} -> {}", path, resp.status()));
        }
        resp.json().await.map_err(|e| e.to_string())
    }

    fn preset_paths(preset: &str) -> &'static [&'static str] {
        match preset {
            "ssdnodes-k8s" => &[
                "ops/k8s/nodes",
                "ops/k8s/pods-not-running",
                "ops/k8s/ingress",
                "ops/k8s/warnings",
            ],
            "ssdnodes-ssh" => &["ops/host/ssh-recent"],
            _ => &["ops/host/disk", "ops/host/memory", "ops/host/load"],
        }
    }

    fn is_compare_message(message: &str) -> bool {
        let m = message.to_lowercase();
        ["compar", " vs ", " versus ", "entre ", " x ", "contra "]
            .iter()
            .any(|n| m.contains(n))
    }

    /// T-334: routing server-side — preset UI é hint, intent manda nos endpoints.
    fn resolve_intent(message: &str, preset: &str) -> ChatIntent {
        if Self::is_conversational_clarification(message) {
            return ChatIntent::General;
        }
        if Self::skip_ops_fetch(message) {
            return ChatIntent::MetaCapabilities;
        }
        let m = message.to_lowercase();
        if Self::is_fleet_resources_message(message) {
            return ChatIntent::FleetResources;
        }
        if Self::is_compare_message(message) {
            return ChatIntent::FleetCompare;
        }
        if m.contains("k8s-node") || m.contains("k8s-master") {
            return ChatIntent::OciNodeQuery;
        }
        if m.contains("ssh")
            || m.contains("fail2ban")
            || m.contains("bruteforce")
            || preset == "ssdnodes-ssh"
        {
            return ChatIntent::SshAudit;
        }
        if m.contains("pod")
            || m.contains("ingress")
            || m.contains("warning")
            || m.contains("namespace")
            || (preset == "ssdnodes-k8s"
                && !m.contains("disco")
                && !m.contains("memória")
                && !m.contains("memoria"))
        {
            return ChatIntent::K8sStatus;
        }
        if m.contains("hetzner")
            || m.contains("aws")
            || m.contains("honeypot")
            || m.contains("172-31")
        {
            return ChatIntent::OciNodeQuery;
        }
        if Self::is_host_health_question(message) {
            return ChatIntent::HostHealth;
        }
        ChatIntent::General
    }

    fn intent_ops_paths(
        intent: ChatIntent,
        preset: &str,
        message: &str,
    ) -> &'static [&'static str] {
        match intent {
            ChatIntent::MetaCapabilities | ChatIntent::OciNodeQuery | ChatIntent::FleetCompare => {
                &[]
            }
            ChatIntent::General if Self::is_conversational_clarification(message) => &[],
            ChatIntent::FleetResources | ChatIntent::HostHealth => {
                Self::preset_paths("ssdnodes-health")
            }
            ChatIntent::K8sStatus => Self::preset_paths("ssdnodes-k8s"),
            ChatIntent::SshAudit => Self::preset_paths("ssdnodes-ssh"),
            ChatIntent::General => Self::preset_paths(preset),
        }
    }

    fn intent_label(intent: ChatIntent) -> &'static str {
        match intent {
            ChatIntent::MetaCapabilities => "meta_capabilities",
            ChatIntent::FleetResources => "fleet_resources",
            ChatIntent::HostHealth => "host_health",
            ChatIntent::K8sStatus => "k8s_status",
            ChatIntent::SshAudit => "ssh_audit",
            ChatIntent::FleetCompare => "fleet_compare",
            ChatIntent::OciNodeQuery => "oci_node_query",
            ChatIntent::General => "general",
        }
    }

    /// Só bypass Gemma para perguntas operacionais explícitas (T-335).
    fn should_structured_bypass(intent: ChatIntent, message: &str) -> bool {
        match intent {
            ChatIntent::FleetResources => true,
            ChatIntent::HostHealth => Self::is_host_health_question(message),
            ChatIntent::K8sStatus => Self::is_k8s_status_question(message),
            ChatIntent::SshAudit => {
                let m = message.to_lowercase();
                m.contains("ssh")
                    || m.contains("fail2ban")
                    || m.contains("bruteforce")
                    || m.contains("login")
            }
            _ => false,
        }
    }

    fn is_host_health_question(message: &str) -> bool {
        let m = message.to_lowercase();
        [
            "disco",
            "memória",
            "memoria",
            "mem ",
            " ram",
            "carga",
            "load average",
            "uptime",
            "df ",
            "free -",
            "espaço",
            "espaco",
            "capacidade",
            "disco cheio",
            "disco no ssd",
            "host/disk",
            "host/memory",
        ]
        .iter()
        .any(|n| m.contains(n))
    }

    fn is_k8s_status_question(message: &str) -> bool {
        let m = message.to_lowercase();
        [
            "pod",
            "ingress",
            "warning",
            "namespace",
            "crashloop",
            "pending",
            "não running",
            "nao running",
            "not running",
        ]
        .iter()
        .any(|n| m.contains(n))
    }

    fn is_conversational_clarification(message: &str) -> bool {
        let m = message.to_lowercase();
        [
            "não foi isso",
            "nao foi isso",
            "não entendeu",
            "nao entendeu",
            "não é isso",
            "nao e isso",
            "perguntei",
            "resposta errada",
            "outra pergunta",
            "tenta de novo",
            "tente de novo",
            "reformulando",
            "não respondeu",
            "nao respondeu",
        ]
        .iter()
        .any(|n| m.contains(n))
    }

    /// Perguntas sobre escopo/inventário — não buscar df/free no gateway (T-332).
    fn skip_ops_fetch(message: &str) -> bool {
        let m = message.to_lowercase();
        [
            "quais hosts",
            "quais host ",
            "quais máquinas",
            "quais maquinas",
            "quais servidores",
            "quais clusters",
            "que hosts",
            "lista de hosts",
            "inventário",
            "inventario",
            "o que você",
            "o que voce",
            "o que faz",
            "o que cobre",
            "o que consegue",
            "consegue fazer",
            "quais nodes",
            "which hosts",
            "what hosts",
            "capabilities",
        ]
        .iter()
        .any(|needle| m.contains(needle))
    }

    /// Perguntas vagas sobre recursos/status — fast-path estruturado (T-335).
    fn is_fleet_resources_message(message: &str) -> bool {
        let m = message.to_lowercase();
        [
            "como estão os recursos",
            "como estao os recursos",
            "como estão os recursos",
            "status da fleet",
            "situação da fleet",
            "situacao da fleet",
            "visão geral",
            "visao geral",
            "panorama",
            "health geral",
            "como está a infra",
            "como esta a infra",
            "como estão as máquinas",
            "como estao as maquinas",
        ]
        .iter()
        .any(|n| m.contains(n))
            || (m.contains("recursos")
                && !m.contains("k8s-node")
                && !m.contains("ssdnodes-6a12f10c"))
    }

    fn ops_stdout_excerpt(context: &Value, key: &str, max_lines: usize) -> Option<String> {
        let stdout = context.get(key)?.get("stdout")?.as_str()?.trim();
        if stdout.is_empty() {
            return None;
        }
        let lines: Vec<&str> = stdout
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .take(max_lines)
            .collect();
        if lines.is_empty() {
            return None;
        }
        Some(lines.join("\n"))
    }

    fn metrics_lines_from_array(nodes: &[Value]) -> Vec<String> {
        let mut lines = Vec::new();
        for node in nodes {
            let name = node
                .get("name")
                .or_else(|| node.get("id"))
                .and_then(|v| v.as_str())
                .unwrap_or("?");
            let cluster = node.get("cluster").and_then(|v| v.as_str()).unwrap_or("?");
            if let Some(metrics) = node.get("metrics") {
                if let Some(line) = Self::format_node_metrics_line(name, cluster, metrics) {
                    lines.push(line);
                }
            }
        }
        lines
    }

    /// Resposta determinística a partir do contexto coletado — evita Gemma (T-335).
    fn structured_reply(
        manifest: &Value,
        context: &Value,
        message: &str,
        preset: &str,
    ) -> Option<String> {
        let intent = Self::resolve_intent(message, preset);
        if intent == ChatIntent::MetaCapabilities {
            return Some(Self::reply_from_manifest(manifest));
        }
        if !Self::should_structured_bypass(intent, message) {
            return None;
        }
        if let Some(reply) = Self::reply_from_targeted_metrics(manifest, intent) {
            return Some(reply);
        }

        let mut parts = vec!["Resumo read-only (sem inferência LLM):".to_string()];

        match intent {
            ChatIntent::HostHealth | ChatIntent::FleetResources => {
                for (key, label) in [
                    ("ops/host/disk", "SSDNodes — disco"),
                    ("ops/host/memory", "SSDNodes — memória"),
                    ("ops/host/load", "SSDNodes — carga"),
                ] {
                    if let Some(excerpt) = Self::ops_stdout_excerpt(context, key, 8) {
                        parts.push(format!("{label}:\n{excerpt}"));
                    }
                }
            }
            ChatIntent::K8sStatus => {
                for (key, label) in [
                    ("ops/k8s/pods-not-running", "Pods não Running"),
                    ("ops/k8s/warnings", "Warnings"),
                    ("ops/k8s/nodes", "Nodes"),
                ] {
                    if let Some(excerpt) = Self::ops_stdout_excerpt(context, key, 12) {
                        parts.push(format!("{label}:\n{excerpt}"));
                    }
                }
            }
            ChatIntent::SshAudit => {
                if let Some(excerpt) = Self::ops_stdout_excerpt(context, "ops/host/ssh-recent", 15)
                {
                    parts.push(format!("SSH recente:\n{excerpt}"));
                }
            }
            _ => {}
        }

        if let Some(snapshot) = manifest
            .get("fleet_metrics_snapshot")
            .and_then(|v| v.as_array())
        {
            let metric_lines = Self::metrics_lines_from_array(snapshot);
            if !metric_lines.is_empty() {
                parts.push(format!(
                    "Prometheus (node_exporter):\n{}",
                    metric_lines.join("\n")
                ));
            }
        }

        if parts.len() > 1 {
            parts.push(
                "Para análise mais profunda, cite um host (@k8s-node-1) ou use consulta rápida na barra lateral."
                    .into(),
            );
            return Some(parts.join("\n\n"));
        }
        None
    }

    fn finalize_reply(
        reply: &str,
        context: Option<&Value>,
        manifest: &Value,
        sources: &[String],
        message: &str,
        preset: &str,
    ) -> String {
        let trimmed = reply.trim();
        let looks_ok = trimmed.len() >= 20
            && !trimmed.to_lowercase().contains("context json")
            && !trimmed.contains("Filesystem     Size")
            && trimmed.matches('{').count() < 4;
        if looks_ok {
            return trimmed.to_string();
        }
        if let Some(ctx) = context {
            let intent = Self::resolve_intent(message, preset);
            if Self::should_structured_bypass(intent, message) {
                if let Some(structured) = Self::structured_reply(manifest, ctx, message, preset) {
                    return structured;
                }
            }
        }
        Self::weak_model_fallback(sources)
    }

    fn format_node_metrics_line(name: &str, cluster: &str, metrics: &Value) -> Option<String> {
        let cpu = metrics.get("cpu_percent")?.as_f64()?;
        let mem_pct = metrics.get("mem_percent")?.as_f64()?;
        let disk_pct = metrics.get("disk_percent")?.as_f64()?;
        Some(format!(
            "- {name} ({cluster}): CPU {cpu:.0}%, mem {mem_pct:.0}%, disco {disk_pct:.0}%"
        ))
    }

    fn targeted_nodes(manifest: &Value) -> Vec<&Value> {
        let mut out = Vec::new();
        for key in ["targeted_oci_nodes", "targeted_external_nodes"] {
            if let Some(arr) = manifest.get(key).and_then(|v| v.as_array()) {
                for n in arr {
                    out.push(n);
                }
            }
        }
        out
    }

    fn reply_from_targeted_metrics(manifest: &Value, intent: ChatIntent) -> Option<String> {
        let nodes = Self::targeted_nodes(manifest);
        if nodes.is_empty() {
            return None;
        }
        let mut lines = Vec::new();
        for node in &nodes {
            let name = node.get("name").and_then(|v| v.as_str()).unwrap_or("?");
            let cluster = node.get("cluster").and_then(|v| v.as_str()).unwrap_or("?");
            let metrics = node.get("metrics")?;
            if let Some(line) = Self::format_node_metrics_line(name, cluster, metrics) {
                lines.push(line);
            }
        }
        if lines.is_empty() {
            return None;
        }
        if intent == ChatIntent::FleetCompare && lines.len() >= 2 {
            return Some(format!(
                "Comparativo read-only (Prometheus/node_exporter):\n{}\n\nDados podem estar ausentes em masters ou hosts sem exporter.",
                lines.join("\n")
            ));
        }
        if nodes.len() == 1 && lines.len() == 1 {
            return Some(format!(
                "Métricas live read-only:\n{}\n\nFonte: Cluster Pulse / Prometheus.",
                lines[0]
            ));
        }
        if lines.len() >= 2 {
            return Some(format!("Métricas live read-only:\n{}", lines.join("\n")));
        }
        None
    }

    /// Resposta imediata para perguntas de escopo (evita timeout do Ollama em CPU).
    fn reply_from_manifest(manifest: &Value) -> String {
        let scope = manifest
            .get("scope")
            .and_then(|s| s.get("description_pt"))
            .and_then(|v| v.as_str())
            .unwrap_or("Assistente read-only da fleet.");
        let mut lines =
            vec!["Hosts e clusters que posso referenciar (dados read-only):".to_string()];
        if let Some(hosts) = manifest.get("hosts").and_then(|h| h.as_array()) {
            for h in hosts {
                let name = h
                    .get("name")
                    .or_else(|| h.get("id"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("?");
                let cluster = h.get("cluster").and_then(|v| v.as_str()).unwrap_or("?");
                let role = h.get("role").and_then(|v| v.as_str()).unwrap_or("");
                let ip = h.get("ip").and_then(|v| v.as_str()).unwrap_or("");
                let src = h.get("source").and_then(|v| v.as_str()).unwrap_or("");
                lines.push(format!("- {name} ({cluster}, {role}) — {ip} [{src}]"));
            }
        }
        lines.push(String::new());
        lines.push(scope.to_string());
        lines.push(
            "Métricas de host no SSDNodes e K8s local: via gateway. Nós OCI-K8s: Cluster Pulse (live overview). \
Pergunte por um host específico para métricas ou compare dois hosts."
                .into(),
        );
        lines.join("\n")
    }

    async fn collect_context(
        &self,
        preset: &str,
        fleet_manifest: Value,
        message: &str,
        history: &[ChatTurn],
    ) -> (Value, Vec<String>) {
        let routing = Self::routing_message(message, history);
        let intent = Self::resolve_intent(&routing, preset);
        let mut context = json!({
            "fleet_manifest": fleet_manifest,
            "intent": Self::intent_label(intent),
        });
        let mut sources = vec!["fleet_manifest".to_string()];
        Self::attach_conversation_history(&mut context, history);

        if intent == ChatIntent::MetaCapabilities {
            return (context, sources);
        }

        let paths = Self::intent_ops_paths(intent, preset, &routing);
        for path in paths {
            match self.fetch_ops(path).await {
                Ok(v) => {
                    sources.push(format!("/{}", path));
                    context[path] = v;
                }
                Err(err) => {
                    context[path] = json!({ "error": err });
                    sources.push(format!("/{} (error)", path));
                }
            }
        }
        (context, sources)
    }

    fn try_fast_reply(manifest: &Value, message: &str, preset: &str) -> Option<String> {
        let intent = Self::resolve_intent(message, preset);
        if intent == ChatIntent::MetaCapabilities {
            return Some(Self::reply_from_manifest(manifest));
        }
        Self::reply_from_targeted_metrics(manifest, intent)
    }

    /// T-334: evita respostas vazias/eco do Gemma — fallback para structured se possível.
    fn sanitize_model_reply(
        reply: &str,
        sources: &[String],
        context: Option<&Value>,
        manifest: Option<&Value>,
        message: &str,
        preset: &str,
    ) -> String {
        if let Some(m) = manifest {
            return Self::finalize_reply(reply, context, m, sources, message, preset);
        }
        let trimmed = reply.trim();
        if trimmed.len() < 20 {
            return Self::weak_model_fallback(sources);
        }
        trimmed.to_string()
    }

    fn weak_model_fallback(sources: &[String]) -> String {
        let src = if sources.is_empty() {
            "fleet_manifest".to_string()
        } else {
            sources.join(", ")
        };
        format!(
            "O modelo local (Gemma 3) gerou uma resposta genérica ou incompleta. \
Confira os dados coletados nas fontes: {src}. \
Tente reformular com um host específico (ex.: k8s-node-1) ou use uma consulta rápida na barra lateral."
        )
    }

    fn clarification_reply() -> String {
        "Beleza — me diga a pergunta exata (ou cole a frase anterior) e, se possível, cite um alvo: \
`ssdnodes-6a12f10c9ef11` ou `@k8s-node-1`. \
\n\nSe você quiser, também posso responder por consultas rápidas: **Disco & memória**, **Pods & ingress**, **SSH 24h**."
            .to_string()
    }
}

pub async fn copilot_session(
    State(fc): State<Arc<FleetCopilotState>>,
    headers: HeaderMap,
) -> Result<Json<SessionResponse>, StatusCode> {
    Ok(Json(SessionResponse {
        authenticated: fc.is_authenticated(&headers),
        enabled: true,
    }))
}

pub async fn copilot_status(
    State(fc): State<Arc<FleetCopilotState>>,
    headers: HeaderMap,
) -> Result<Json<StatusResponse>, StatusCode> {
    if !fc.check_auth(&headers) {
        return Err(StatusCode::NOT_FOUND);
    }
    let client_key = headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("local")
        .split(',')
        .next()
        .unwrap_or("local")
        .trim()
        .to_string();
    let gateway_reachable = fc.gateway_reachable().await;
    let rate_limit_remaining = fc.rate_remaining(&client_key).await;
    Ok(Json(StatusResponse {
        authenticated: true,
        enabled: true,
        gateway_reachable,
        ollama_model: fc.ollama_model.clone(),
        inference_mode: "llm-default-structured-fast-path",
        structured_models: vec!["fleet-manifest", "fleet-metrics", "fleet-structured"],
        rate_limit_max: RATE_MAX,
        rate_limit_remaining,
        thread_context: true,
    }))
}

pub async fn copilot_login(
    State(fc): State<Arc<FleetCopilotState>>,
    Query(query): Query<LoginQuery>,
) -> Response {
    let Some(key) = query.key else {
        return StatusCode::NOT_FOUND.into_response();
    };
    if key != fc.login_key {
        return StatusCode::NOT_FOUND.into_response();
    }

    let cookie = format!(
        "{}={}; Path=/; HttpOnly; Secure; Max-Age=28800; SameSite=Lax",
        COOKIE_NAME,
        fc.session_cookie_value()
    );

    let mut resp = Response::builder()
        .status(StatusCode::FOUND)
        .header(header::LOCATION, "/#fleet-copilot")
        .body(axum::body::Body::empty())
        .unwrap();
    resp.headers_mut()
        .insert(header::SET_COOKIE, cookie.parse().unwrap());
    resp
}

pub async fn copilot_logout() -> Response {
    let cookie = format!(
        "{}=; Path=/; HttpOnly; Secure; Max-Age=0; SameSite=Lax",
        COOKIE_NAME
    );
    let mut resp = StatusCode::NO_CONTENT.into_response();
    resp.headers_mut()
        .insert(header::SET_COOKIE, cookie.parse().unwrap());
    resp
}

pub async fn copilot_chat(
    State(fc): State<Arc<FleetCopilotState>>,
    fleet_manifest: Value,
    headers: HeaderMap,
    Json(body): Json<ChatRequest>,
) -> Result<Json<ChatResponse>, StatusCode> {
    if !fc.is_authenticated(&headers) {
        return Err(StatusCode::NOT_FOUND);
    }

    let client_key = headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("local")
        .split(',')
        .next()
        .unwrap_or("local")
        .trim()
        .to_string();

    if !fc.check_rate(&client_key).await {
        return Err(StatusCode::TOO_MANY_REQUESTS);
    }

    let message = body.message.trim();
    if message.is_empty() || message.len() > MAX_BODY_MSG {
        return Err(StatusCode::BAD_REQUEST);
    }

    let history = FleetCopilotState::normalize_history(body.history);
    let preset = body.preset.as_deref().unwrap_or("ssdnodes-health");
    let started = Instant::now();
    let client_ip = headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|raw| raw.split(',').next())
        .map(|s| s.trim().to_string());

    if FleetCopilotState::should_clarification_fast_path(message, &history) {
        let latency_ms = started.elapsed().as_millis() as u64;
        let sources = vec!["fleet_manifest".to_string()];
        fc.audit_event(AuditEvent {
            client_ip: client_ip.as_deref(),
            message,
            preset,
            intent: "clarification",
            endpoints: &sources,
            latency_ms,
            model: "fleet-meta",
            status: "ok",
        })
        .await;
        return Ok(Json(ChatResponse {
            reply: FleetCopilotState::clarification_reply(),
            model: "fleet-meta".into(),
            sources,
            latency_ms,
        }));
    }

    let routing = FleetCopilotState::routing_message(message, &history);
    let llm_message = FleetCopilotState::llm_message(message, &history);

    if let Some(reply) = FleetCopilotState::try_fast_reply(
        &fleet_manifest,
        routing.as_ref(),
        preset,
    ) {
        let intent = FleetCopilotState::resolve_intent(routing.as_ref(), preset);
        let model = if intent == ChatIntent::MetaCapabilities {
            "fleet-manifest"
        } else {
            "fleet-metrics"
        };
        let latency_ms = started.elapsed().as_millis() as u64;
        let intent_label = FleetCopilotState::intent_label(intent).to_string();
        let sources = vec!["fleet_manifest".to_string()];
        fc.audit_event(AuditEvent {
            client_ip: client_ip.as_deref(),
            message,
            preset,
            intent: &intent_label,
            endpoints: &sources,
            latency_ms,
            model,
            status: "ok",
        })
        .await;
        return Ok(Json(ChatResponse {
            reply,
            model: model.into(),
            sources,
            latency_ms,
        }));
    }

    let (context, sources) = fc
        .collect_context(preset, fleet_manifest.clone(), message, &history)
        .await;

    if !FleetCopilotState::should_skip_structured(message, &history) {
        if let Some(reply) =
            FleetCopilotState::structured_reply(&fleet_manifest, &context, routing.as_ref(), preset)
        {
            let latency_ms = started.elapsed().as_millis() as u64;
            let intent = FleetCopilotState::resolve_intent(routing.as_ref(), preset);
            let intent_label = FleetCopilotState::intent_label(intent).to_string();
            fc.audit_event(AuditEvent {
                client_ip: client_ip.as_deref(),
                message,
                preset,
                intent: &intent_label,
                endpoints: &sources,
                latency_ms,
                model: "fleet-structured",
                status: "ok",
            })
            .await;
            return Ok(Json(ChatResponse {
                reply,
                model: "fleet-structured".into(),
                sources,
                latency_ms,
            }));
        }
    }

    let url = format!("{}/internal/chat", fc.gateway_url.trim_end_matches('/'));
    let chat_resp = fc
        .client
        .post(&url)
        .header(header::AUTHORIZATION, fc.auth_header())
        .json(&json!({
            "message": llm_message,
            "context": context
        }))
        .send()
        .await
        .map_err(|_| StatusCode::BAD_GATEWAY)?;

    if !chat_resp.status().is_success() {
        return Err(StatusCode::BAD_GATEWAY);
    }

    let parsed: Value = chat_resp
        .json()
        .await
        .map_err(|_| StatusCode::BAD_GATEWAY)?;
    let reply = FleetCopilotState::sanitize_model_reply(
        parsed["reply"]
            .as_str()
            .unwrap_or("Sem resposta do modelo."),
        &sources,
        Some(&context),
        context.get("fleet_manifest"),
        message,
        preset,
    );
    let model = parsed["model"].as_str().unwrap_or("gemma3:4b").to_string();
    let latency_ms = started.elapsed().as_millis() as u64;
    let intent = FleetCopilotState::resolve_intent(message, preset);
    let intent_label = FleetCopilotState::intent_label(intent).to_string();
    fc.audit_event(AuditEvent {
        client_ip: client_ip.as_deref(),
        message,
        preset,
        intent: &intent_label,
        endpoints: &sources,
        latency_ms,
        model: &model,
        status: "ok",
    })
    .await;

    Ok(Json(ChatResponse {
        reply,
        model,
        sources,
        latency_ms,
    }))
}

pub async fn copilot_chat_stream(
    State(fc): State<Arc<FleetCopilotState>>,
    fleet_manifest: Value,
    headers: HeaderMap,
    Json(body): Json<ChatRequest>,
) -> Result<Sse<impl futures_util::Stream<Item = Result<Event, Infallible>>>, StatusCode> {
    if !fc.is_authenticated(&headers) {
        return Err(StatusCode::NOT_FOUND);
    }

    let client_key = headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("local")
        .split(',')
        .next()
        .unwrap_or("local")
        .trim()
        .to_string();

    if !fc.check_rate(&client_key).await {
        return Err(StatusCode::TOO_MANY_REQUESTS);
    }

    let message = body.message.trim();
    if message.is_empty() || message.len() > MAX_BODY_MSG {
        return Err(StatusCode::BAD_REQUEST);
    }

    let preset = body
        .preset
        .as_deref()
        .unwrap_or("ssdnodes-health")
        .to_string();
    let history = FleetCopilotState::normalize_history(body.history);
    let fc = fc.clone();
    let message = message.to_string();
    let fleet_manifest_for_reply = fleet_manifest.clone();
    let client_ip = headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|raw| raw.split(',').next())
        .map(|s| s.trim().to_string());

    let (tx, rx) = tokio::sync::mpsc::channel::<Result<Event, Infallible>>(64);
    tokio::spawn(async move {
        let send = |event: Event| async { tx.send(Ok(event)).await.is_ok() };

        if !send(
            Event::default()
                .event("phase")
                .data(json!({ "phase": "collect" }).to_string()),
        )
        .await
        {
            return;
        }

        let started = Instant::now();
        let routing = FleetCopilotState::routing_message(&message, &history);
        let llm_message = FleetCopilotState::llm_message(&message, &history);

        if FleetCopilotState::should_clarification_fast_path(&message, &history) {
            let sources = vec!["fleet_manifest".to_string()];
            fc.audit_event(AuditEvent {
                client_ip: client_ip.as_deref(),
                message: &message,
                preset: &preset,
                intent: "clarification",
                endpoints: &sources,
                latency_ms: started.elapsed().as_millis() as u64,
                model: "fleet-meta",
                status: "ok",
            })
            .await;
            let _ = send(
                Event::default().event("done").data(
                    json!({
                        "reply": FleetCopilotState::clarification_reply(),
                        "model": "fleet-meta",
                        "sources": ["fleet_manifest"],
                        "latency_ms": started.elapsed().as_millis() as u64,
                    })
                    .to_string(),
                ),
            )
            .await;
            return;
        }

        if let Some(reply) =
            FleetCopilotState::try_fast_reply(&fleet_manifest, routing.as_ref(), &preset)
        {
            let intent = FleetCopilotState::resolve_intent(routing.as_ref(), &preset);
            let model = if intent == ChatIntent::MetaCapabilities {
                "fleet-manifest"
            } else {
                "fleet-metrics"
            };
            let sources = vec!["fleet_manifest".to_string()];
            let intent_label = FleetCopilotState::intent_label(intent).to_string();
            fc.audit_event(AuditEvent {
                client_ip: client_ip.as_deref(),
                message: &message,
                preset: &preset,
                intent: &intent_label,
                endpoints: &sources,
                latency_ms: started.elapsed().as_millis() as u64,
                model,
                status: "ok",
            })
            .await;
            let _ = send(
                Event::default()
                    .event("phase")
                    .data(json!({ "phase": "infer", "sources": sources }).to_string()),
            )
            .await;
            let _ = send(
                Event::default().event("done").data(
                    json!({
                        "reply": reply,
                        "model": model,
                        "sources": ["fleet_manifest"],
                        "latency_ms": started.elapsed().as_millis() as u64,
                    })
                    .to_string(),
                ),
            )
            .await;
            return;
        }

        let (context, sources) = fc
            .collect_context(&preset, fleet_manifest, &message, &history)
            .await;

        if !FleetCopilotState::should_skip_structured(&message, &history) {
            if let Some(reply) = FleetCopilotState::structured_reply(
                &fleet_manifest_for_reply,
                &context,
                routing.as_ref(),
                &preset,
            ) {
                let intent = FleetCopilotState::resolve_intent(routing.as_ref(), &preset);
                let intent_label = FleetCopilotState::intent_label(intent).to_string();
                fc.audit_event(AuditEvent {
                    client_ip: client_ip.as_deref(),
                    message: &message,
                    preset: &preset,
                    intent: &intent_label,
                    endpoints: &sources,
                    latency_ms: started.elapsed().as_millis() as u64,
                    model: "fleet-structured",
                    status: "ok",
                })
                .await;
                let _ = send(
                    Event::default()
                        .event("phase")
                        .data(json!({ "phase": "infer", "sources": sources.clone() }).to_string()),
                )
                .await;
                let _ = send(
                    Event::default().event("done").data(
                        json!({
                            "reply": reply,
                            "model": "fleet-structured",
                            "sources": sources,
                            "latency_ms": started.elapsed().as_millis() as u64,
                        })
                        .to_string(),
                    ),
                )
                .await;
                return;
            }
        }

        if !send(
            Event::default()
                .event("phase")
                .data(json!({ "phase": "infer", "sources": sources.clone() }).to_string()),
        )
        .await
        {
            return;
        }

        let url = format!(
            "{}/internal/chat/stream",
            fc.gateway_url.trim_end_matches('/')
        );

        let resp = match fc
            .client
            .post(&url)
            .header(header::AUTHORIZATION, fc.auth_header())
            .json(&json!({
                "message": llm_message,
                "context": context
            }))
            .send()
            .await
        {
            Ok(r) => r,
            Err(_) => {
                let _ = send(
                    Event::default()
                        .event("error")
                        .data(json!({ "message": "gateway unreachable" }).to_string()),
                )
                .await;
                return;
            }
        };

        if !resp.status().is_success() {
            let _ = send(Event::default().event("error").data(
                json!({ "message": format!("gateway status {}", resp.status()) }).to_string(),
            ))
            .await;
            return;
        }

        let mut byte_stream = resp.bytes_stream();
        let mut buffer = String::new();
        let mut got_done = false;
        let mut streamed_reply = String::new();

        let sources_for_sanitize = sources.clone();
        let context_for_sanitize = context.clone();
        let message_for_sanitize = message.clone();
        let preset_for_sanitize = preset.clone();

        let mut forward_block = |event_name: &str, mut data: String| -> bool {
            if event_name == "token" {
                if let Ok(val) = serde_json::from_str::<Value>(&data) {
                    if let Some(delta) = val["delta"].as_str() {
                        streamed_reply.push_str(delta);
                    }
                }
            }
            if event_name == "done" {
                got_done = true;
                if let Ok(mut val) = serde_json::from_str::<Value>(&data) {
                    if let Some(obj) = val.as_object_mut() {
                        let raw = obj.get("reply").and_then(|v| v.as_str()).unwrap_or("");
                        let merged = if streamed_reply.len() > raw.len() {
                            streamed_reply.as_str()
                        } else {
                            raw
                        };
                        obj.insert(
                            "reply".into(),
                            json!(FleetCopilotState::sanitize_model_reply(
                                merged,
                                &sources_for_sanitize,
                                Some(&context_for_sanitize),
                                context_for_sanitize.get("fleet_manifest"),
                                &message_for_sanitize,
                                &preset_for_sanitize,
                            )),
                        );
                    }
                    data = val.to_string();
                }
            }
            tx.send(Ok(Event::default().event(event_name).data(data)))
                .now_or_never()
                .is_some()
        };

        while let Some(chunk) = byte_stream.next().await {
            let chunk = match chunk {
                Ok(c) => c,
                Err(_) => break,
            };
            buffer.push_str(&String::from_utf8_lossy(&chunk));

            while let Some(pos) = buffer.find("\n\n") {
                let block = buffer[..pos].to_string();
                buffer.drain(..pos + 2);

                if let Some((event_name, mut data)) = parse_sse_block(&block) {
                    if event_name == "done" {
                        if let Ok(mut val) = serde_json::from_str::<Value>(&data) {
                            if let Some(obj) = val.as_object_mut() {
                                obj.insert("sources".into(), json!(sources));
                                obj.insert(
                                    "latency_ms".into(),
                                    json!(started.elapsed().as_millis() as u64),
                                );
                            }
                            data = val.to_string();
                        }
                        let intent = FleetCopilotState::resolve_intent(
                            &message_for_sanitize,
                            &preset_for_sanitize,
                        );
                        let intent_label = FleetCopilotState::intent_label(intent).to_string();
                        fc.audit_event(AuditEvent {
                            client_ip: client_ip.as_deref(),
                            message: &message_for_sanitize,
                            preset: &preset_for_sanitize,
                            intent: &intent_label,
                            endpoints: &sources,
                            latency_ms: started.elapsed().as_millis() as u64,
                            model: "ollama",
                            status: "ok",
                        })
                        .await;
                        if !forward_block("done", data) {
                            return;
                        }
                        return;
                    }
                    if !forward_block(&event_name, data) {
                        return;
                    }
                }
            }
        }

        // Flush trailing SSE (evita perder `done` se o chunk fechar sem \n\n final)
        while let Some(pos) = buffer.find("\n\n") {
            let block = buffer[..pos].to_string();
            buffer.drain(..pos + 2);
            if let Some((event_name, mut data)) = parse_sse_block(&block) {
                if event_name == "done" {
                    if let Ok(mut val) = serde_json::from_str::<Value>(&data) {
                        if let Some(obj) = val.as_object_mut() {
                            obj.insert("sources".into(), json!(sources));
                            obj.insert(
                                "latency_ms".into(),
                                json!(started.elapsed().as_millis() as u64),
                            );
                        }
                        data = val.to_string();
                    }
                    let _ = forward_block("done", data);
                    return;
                }
                if !forward_block(&event_name, data) {
                    return;
                }
            }
        }
        if !buffer.trim().is_empty() {
            if let Some((event_name, data)) = parse_sse_block(buffer.trim()) {
                if event_name == "done" {
                    let _ = forward_block("done", data);
                    return;
                }
                let _ = forward_block(&event_name, data);
            }
        }

        if !got_done && !streamed_reply.is_empty() {
            let reply = FleetCopilotState::sanitize_model_reply(
                &streamed_reply,
                &sources,
                Some(&context),
                context.get("fleet_manifest"),
                &message,
                &preset,
            );
            let _ = send(
                Event::default().event("done").data(
                    json!({
                        "reply": reply,
                        "partial": true,
                        "sources": sources,
                        "latency_ms": started.elapsed().as_millis() as u64,
                    })
                    .to_string(),
                ),
            )
            .await;
        } else if !got_done {
            let _ = send(
                Event::default().event("error").data(
                    json!({ "message": "stream encerrado antes da conclusão — tente novamente" })
                        .to_string(),
                ),
            )
            .await;
        }
    });

    Ok(Sse::new(ReceiverStream::new(rx))
        .keep_alive(KeepAlive::new().interval(Duration::from_secs(15))))
}

fn parse_sse_block(block: &str) -> Option<(String, String)> {
    let mut event_name = "message".to_string();
    let mut data = String::new();
    for line in block.lines() {
        if let Some(v) = line.strip_prefix("event:") {
            event_name = v.trim().to_string();
        } else if let Some(v) = line.strip_prefix("data:") {
            if !data.is_empty() {
                data.push('\n');
            }
            data.push_str(v.trim());
        }
    }
    if data.is_empty() {
        return None;
    }
    Some((event_name, data))
}

#[cfg(test)]
mod tests {
    use super::FleetCopilotState;
    use serde_json::json;

    #[test]
    fn skip_ops_for_meta_questions() {
        assert!(FleetCopilotState::skip_ops_fetch(
            "Quais hosts você analisa?"
        ));
        assert!(!FleetCopilotState::skip_ops_fetch(
            "Como está o disco no SSDNodes?"
        ));
    }

    #[test]
    fn intent_routes_k8s_questions() {
        assert_eq!(
            FleetCopilotState::resolve_intent("pods not running?", "ssdnodes-health"),
            super::ChatIntent::K8sStatus
        );
        assert_eq!(
            FleetCopilotState::resolve_intent("memória k8s-node-1", "ssdnodes-health"),
            super::ChatIntent::OciNodeQuery
        );
        assert_eq!(
            FleetCopilotState::resolve_intent(
                "Compare disco SSDNodes vs hetzner",
                "ssdnodes-health"
            ),
            super::ChatIntent::FleetCompare
        );
    }

    #[test]
    fn metrics_fast_reply_from_targeted_nodes() {
        let manifest = json!({
            "targeted_oci_nodes": [{
                "name": "k8s-node-1",
                "cluster": "OCI",
                "metrics": {
                    "cpu_percent": 12.0,
                    "mem_percent": 45.0,
                    "disk_percent": 60.0
                }
            }]
        });
        let reply = FleetCopilotState::reply_from_targeted_metrics(
            &manifest,
            super::ChatIntent::OciNodeQuery,
        );
        assert!(reply.unwrap().contains("k8s-node-1"));
    }

    #[test]
    fn sanitize_replaces_echo_reply() {
        let weak = "Context JSON: {\"stdout\": \"Filesystem\"}";
        let ctx = json!({
            "ops/host/disk": { "stdout": "Filesystem      Size  Used Avail Use%\n/dev/sda1        1T  100G  900G  10% /" }
        });
        let manifest = json!({ "hosts": [] });
        let out = FleetCopilotState::sanitize_model_reply(
            weak,
            &["/ops/host/disk".into()],
            Some(&ctx),
            Some(&manifest),
            "disco?",
            "ssdnodes-health",
        );
        assert!(out.contains("SSDNodes") || out.contains("/dev/"));
    }

    #[test]
    fn fleet_resources_intent() {
        assert_eq!(
            FleetCopilotState::resolve_intent("Como estão os recursos?", "ssdnodes-health"),
            super::ChatIntent::FleetResources
        );
    }

    #[test]
    fn structured_reply_from_ops() {
        let ctx = json!({
            "ops/host/memory": { "stdout": "Mem: 64Gi total, 32Gi used" }
        });
        let manifest = json!({ "hosts": [] });
        let reply = FleetCopilotState::structured_reply(
            &manifest,
            &ctx,
            "Como estão os recursos?",
            "ssdnodes-health",
        );
        assert!(reply.unwrap().contains("memória"));
    }

    #[test]
    fn clarification_uses_llm_not_structured_template() {
        let ctx = json!({
            "ops/host/disk": { "stdout": "Filesystem 1T" },
            "ops/host/memory": { "stdout": "Mem: 60Gi" },
            "ops/host/load": { "stdout": "load 0.5" }
        });
        let manifest = json!({ "hosts": [] });
        assert_eq!(
            FleetCopilotState::resolve_intent("nao foi isso que perguntei", "ssdnodes-health"),
            super::ChatIntent::General
        );
        assert!(FleetCopilotState::structured_reply(
            &manifest,
            &ctx,
            "nao foi isso que perguntei",
            "ssdnodes-health"
        )
        .is_none());
        assert!(!FleetCopilotState::should_structured_bypass(
            super::ChatIntent::General,
            "nao foi isso que perguntei"
        ));
    }

    #[test]
    fn host_health_requires_explicit_topic() {
        assert_eq!(
            FleetCopilotState::resolve_intent("nao foi isso que perguntei", "ssdnodes-health"),
            super::ChatIntent::General
        );
        assert_eq!(
            FleetCopilotState::resolve_intent("Como está o disco no SSDNodes?", "ssdnodes-health"),
            super::ChatIntent::HostHealth
        );
        assert!(FleetCopilotState::should_structured_bypass(
            super::ChatIntent::HostHealth,
            "Como está o disco no SSDNodes?"
        ));
    }

    #[test]
    fn history_normalization_caps_turns_and_roles() {
        let raw: Vec<super::ChatTurn> = (0..12)
            .map(|i| super::ChatTurn {
                role: if i % 2 == 0 {
                    "user".into()
                } else {
                    "assistant".into()
                },
                content: format!("msg-{i}"),
            })
            .collect();
        let out = FleetCopilotState::normalize_history(raw);
        assert_eq!(out.len(), 8);
        assert_eq!(out[0].content, "msg-4");
        assert_eq!(out[7].content, "msg-11");
    }

    #[test]
    fn clarification_with_history_skips_structured_and_rewinds_routing() {
        let history = vec![
            super::ChatTurn {
                role: "user".into(),
                content: "Como está o disco no SSDNodes?".into(),
            },
            super::ChatTurn {
                role: "assistant".into(),
                content: "Resposta genérica errada".into(),
            },
        ];
        assert!(!FleetCopilotState::should_clarification_fast_path(
            "nao foi isso que perguntei",
            &history
        ));
        assert!(FleetCopilotState::should_skip_structured(
            "nao foi isso que perguntei",
            &history
        ));
        let routing = FleetCopilotState::routing_message("nao foi isso que perguntei", &history);
        assert!(routing.contains("disco"));
        let llm = FleetCopilotState::llm_message("nao foi isso que perguntei", &history);
        assert!(llm.contains("Reavaliando"));
    }
}
