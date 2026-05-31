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
    collections::HashMap,
    convert::Infallible,
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::sync::Mutex;
use tokio_stream::wrappers::ReceiverStream;

const COOKIE_NAME: &str = "fleet-copilot-session";
const MAX_BODY_MSG: usize = 4000;
const RATE_WINDOW: Duration = Duration::from_secs(60);
const RATE_MAX: usize = 10;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ChatIntent {
    MetaCapabilities,
    HostHealth,
    K8sStatus,
    SshAudit,
    FleetCompare,
    OciNodeQuery,
}

#[derive(Clone)]
pub struct FleetCopilotState {
    login_key: String,
    session_token: String,
    gateway_url: String,
    gateway_token: String,
    client: Client,
    rate: Arc<Mutex<HashMap<String, Vec<Instant>>>>,
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

#[derive(Deserialize)]
pub struct ChatRequest {
    pub message: String,
    #[serde(default)]
    pub preset: Option<String>,
}

#[derive(Serialize)]
pub struct ChatResponse {
    pub reply: String,
    pub model: String,
    pub sources: Vec<String>,
    pub latency_ms: u64,
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
            client,
            rate: Arc::new(Mutex::new(HashMap::new())),
        }))
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
        [
            "compar", " vs ", " versus ", "entre ", " x ", "contra ",
        ]
        .iter()
        .any(|n| m.contains(n))
    }

    /// T-334: routing server-side — preset UI é hint, intent manda nos endpoints.
    fn resolve_intent(message: &str, preset: &str) -> ChatIntent {
        if Self::skip_ops_fetch(message) {
            return ChatIntent::MetaCapabilities;
        }
        let m = message.to_lowercase();
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
        ChatIntent::HostHealth
    }

    fn intent_ops_paths(intent: ChatIntent) -> &'static [&'static str] {
        match intent {
            ChatIntent::MetaCapabilities | ChatIntent::OciNodeQuery | ChatIntent::FleetCompare => {
                &[]
            }
            ChatIntent::K8sStatus => Self::preset_paths("ssdnodes-k8s"),
            ChatIntent::SshAudit => Self::preset_paths("ssdnodes-ssh"),
            ChatIntent::HostHealth => Self::preset_paths("ssdnodes-health"),
        }
    }

    fn intent_label(intent: ChatIntent) -> &'static str {
        match intent {
            ChatIntent::MetaCapabilities => "meta_capabilities",
            ChatIntent::HostHealth => "host_health",
            ChatIntent::K8sStatus => "k8s_status",
            ChatIntent::SshAudit => "ssh_audit",
            ChatIntent::FleetCompare => "fleet_compare",
            ChatIntent::OciNodeQuery => "oci_node_query",
        }
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
            "quais nodes",
            "which hosts",
            "what hosts",
            "capabilities",
        ]
        .iter()
        .any(|needle| m.contains(needle))
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
        let mut lines = vec![
            "Hosts e clusters que posso referenciar (dados read-only):".to_string(),
        ];
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
                lines.push(format!(
                    "- {name} ({cluster}, {role}) — {ip} [{src}]"
                ));
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
    ) -> (Value, Vec<String>) {
        let intent = Self::resolve_intent(message, preset);
        let mut context = json!({
            "fleet_manifest": fleet_manifest,
            "intent": Self::intent_label(intent),
        });
        let mut sources = vec!["fleet_manifest".to_string()];

        if intent == ChatIntent::MetaCapabilities {
            return (context, sources);
        }

        let paths = Self::intent_ops_paths(intent);
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

    /// T-334: evita respostas vazias/eco do Gemma.
    fn sanitize_model_reply(reply: &str, sources: &[String]) -> String {
        let trimmed = reply.trim();
        if trimmed.len() < 20 {
            return Self::weak_model_fallback(sources);
        }
        let lc = trimmed.to_lowercase();
        if lc.contains("context json")
            || lc.contains("\"stdout\"")
            || lc.contains("filesystem     size")
            || trimmed.matches('{').count() >= 4
        {
            return Self::weak_model_fallback(sources);
        }
        if (lc.contains("como assistente") || lc.contains("as an ai"))
            && trimmed.len() < 120
        {
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

    let preset = body.preset.as_deref().unwrap_or("ssdnodes-health");
    let started = Instant::now();

    if let Some(reply) = FleetCopilotState::try_fast_reply(&fleet_manifest, message, preset) {
        let intent = FleetCopilotState::resolve_intent(message, preset);
        let model = if intent == ChatIntent::MetaCapabilities {
            "fleet-manifest"
        } else {
            "fleet-metrics"
        };
        return Ok(Json(ChatResponse {
            reply,
            model: model.into(),
            sources: vec!["fleet_manifest".into()],
            latency_ms: started.elapsed().as_millis() as u64,
        }));
    }

    let (context, sources) = fc
        .collect_context(preset, fleet_manifest, message)
        .await;

    let url = format!("{}/internal/chat", fc.gateway_url.trim_end_matches('/'));
    let chat_resp = fc
        .client
        .post(&url)
        .header(header::AUTHORIZATION, fc.auth_header())
        .json(&json!({
            "message": message,
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
    );
    let model = parsed["model"].as_str().unwrap_or("gemma3:4b").to_string();

    Ok(Json(ChatResponse {
        reply,
        model,
        sources,
        latency_ms: started.elapsed().as_millis() as u64,
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
    let fc = fc.clone();
    let message = message.to_string();

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

        if let Some(reply) =
            FleetCopilotState::try_fast_reply(&fleet_manifest, &message, &preset)
        {
            let intent = FleetCopilotState::resolve_intent(&message, &preset);
            let model = if intent == ChatIntent::MetaCapabilities {
                "fleet-manifest"
            } else {
                "fleet-metrics"
            };
            let sources = vec!["fleet_manifest".to_string()];
            let _ = send(
                Event::default()
                    .event("phase")
                    .data(json!({ "phase": "infer", "sources": sources }).to_string()),
            )
            .await;
            let _ = send(
                Event::default()
                    .event("done")
                    .data(
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
            .collect_context(&preset, fleet_manifest, &message)
            .await;

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
                "message": message,
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
                        let raw = obj
                            .get("reply")
                            .and_then(|v| v.as_str())
                            .unwrap_or("");
                        let merged = if streamed_reply.len() > raw.len() {
                            streamed_reply.as_str()
                        } else {
                            raw
                        };
                        obj.insert(
                            "reply".into(),
                            json!(FleetCopilotState::sanitize_model_reply(
                                merged,
                                &sources_for_sanitize
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
            let reply = FleetCopilotState::sanitize_model_reply(&streamed_reply, &sources);
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
        let out = FleetCopilotState::sanitize_model_reply(&weak, &["/ops/host/disk".into()]);
        assert!(out.contains("genérica ou incompleta"));
    }
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
