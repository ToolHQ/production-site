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

    async fn collect_context(&self, preset: &str) -> (Value, Vec<String>) {
        let paths = Self::preset_paths(preset);
        let mut context = json!({});
        let mut sources = Vec::new();
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
    let (context, sources) = fc.collect_context(preset).await;

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
    let reply = parsed["reply"]
        .as_str()
        .unwrap_or("Sem resposta do modelo.")
        .to_string();
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
        let (context, sources) = fc.collect_context(&preset).await;

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

        let mut forward_block =
            |event_name: &str, data: &str| -> bool {
                if event_name == "token" {
                    if let Ok(val) = serde_json::from_str::<Value>(data) {
                        if let Some(delta) = val["delta"].as_str() {
                            streamed_reply.push_str(delta);
                        }
                    }
                }
                if event_name == "done" {
                    got_done = true;
                }
                tx.send(Ok(
                    Event::default()
                        .event(event_name)
                        .data(data.to_string()),
                ))
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
                        if !forward_block("done", &data) {
                            return;
                        }
                        return;
                    }
                    if !forward_block(&event_name, &data) {
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
                    let _ = forward_block("done", &data);
                    return;
                }
                if !forward_block(&event_name, &data) {
                    return;
                }
            }
        }
        if !buffer.trim().is_empty() {
            if let Some((event_name, data)) = parse_sse_block(buffer.trim()) {
                if event_name == "done" {
                    let _ = forward_block("done", &data);
                    return;
                }
                let _ = forward_block(&event_name, &data);
            }
        }

        if !got_done && !streamed_reply.is_empty() {
            let _ = send(
                Event::default().event("done").data(
                    json!({
                        "reply": streamed_reply,
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
