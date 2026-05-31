use axum::{
    extract::{Request, State},
    http::{header, StatusCode},
    middleware::{self, Next},
    response::{
        sse::{Event, KeepAlive, Sse},
        IntoResponse, Response,
    },
    routing::{get, post},
    Json, Router,
};
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::convert::Infallible;
use std::{
    env,
    net::SocketAddr,
    process::Stdio,
    sync::Arc,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tokio::{process::Command, time::timeout};
use tokio_stream::wrappers::ReceiverStream;

const CMD_TIMEOUT: Duration = Duration::from_secs(15);
const OLLAMA_TIMEOUT: Duration = Duration::from_secs(180);

fn ollama_client() -> Result<reqwest::Client, String> {
    reqwest::Client::builder()
        .timeout(OLLAMA_TIMEOUT)
        .no_gzip()
        .no_brotli()
        .no_deflate()
        .tcp_keepalive(Duration::from_secs(60))
        .pool_idle_timeout(Duration::from_secs(90))
        .build()
        .map_err(|e| e.to_string())
}

fn ollama_chat_payload(model: &str, system: &str, user: &str, stream: bool) -> Value {
    json!({
        "model": model,
        "stream": stream,
        "keep_alive": "15m",
        "options": { "num_ctx": 8192, "num_predict": 512, "temperature": 0.3 },
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user}
        ]
    })
}

#[derive(Clone)]
struct AppState {
    gateway_token: Arc<String>,
    ollama_model: String,
}

#[derive(Serialize)]
struct OpsEnvelope {
    endpoint: &'static str,
    collected_at: String,
    exit_code: i32,
    stdout: String,
    stderr: String,
}

#[derive(Deserialize)]
struct ChatRequest {
    message: String,
    #[serde(default)]
    context: Value,
}

#[derive(Serialize)]
struct ChatResponse {
    reply: String,
    model: String,
    sources: Vec<String>,
}

#[tokio::main]
async fn main() {
    let bind = env::var("FLEET_GATEWAY_BIND").unwrap_or_else(|_| "0.0.0.0:18443".into());
    let token = env::var("FLEET_GATEWAY_TOKEN").unwrap_or_else(|_| {
        eprintln!("FLEET_GATEWAY_TOKEN is required");
        std::process::exit(1);
    });
    let ollama_model = env::var("FLEET_OLLAMA_MODEL").unwrap_or_else(|_| "gemma3:4b".into());

    let state = AppState {
        gateway_token: Arc::new(token),
        ollama_model,
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/ops/host/disk", get(ops_host_disk))
        .route("/ops/host/memory", get(ops_host_memory))
        .route("/ops/host/load", get(ops_host_load))
        .route("/ops/host/services-failed", get(ops_services_failed))
        .route("/ops/host/ssh-recent", get(ops_ssh_recent))
        .route("/ops/k8s/nodes", get(ops_k8s_nodes))
        .route("/ops/k8s/pods-not-running", get(ops_k8s_pods_not_running))
        .route("/ops/k8s/ingress", get(ops_k8s_ingress))
        .route("/ops/k8s/warnings", get(ops_k8s_warnings))
        .route("/internal/chat", post(internal_chat))
        .route("/internal/chat/stream", post(internal_chat_stream))
        .layer(middleware::from_fn_with_state(state.clone(), require_auth))
        .with_state(state);

    let addr: SocketAddr = bind.parse().expect("invalid FLEET_GATEWAY_BIND");
    println!("fleet-ops-gateway listening on http://{addr}");
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .unwrap_or_else(|e| panic!("bind {addr}: {e}"));
    axum::serve(listener, app).await.expect("serve");
}

async fn require_auth(State(state): State<AppState>, request: Request, next: Next) -> Response {
    if request.uri().path() == "/health" {
        return next.run(request).await;
    }
    let authorized = request
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .is_some_and(|h| h == format!("Bearer {}", state.gateway_token.as_str()));
    if !authorized {
        return StatusCode::NOT_FOUND.into_response();
    }
    next.run(request).await
}

async fn health() -> Json<Value> {
    Json(json!({ "status": "ok", "service": "fleet-ops-gateway" }))
}

async fn ops_host_disk(State(_): State<AppState>) -> Json<OpsEnvelope> {
    run_ops("/ops/host/disk", &["df", "-h"]).await
}

async fn ops_host_memory(State(_): State<AppState>) -> Json<OpsEnvelope> {
    run_ops("/ops/host/memory", &["free", "-h"]).await
}

async fn ops_host_load(State(_): State<AppState>) -> Json<OpsEnvelope> {
    run_ops("/ops/host/load", &["uptime"]).await
}

async fn ops_services_failed(State(_): State<AppState>) -> Json<OpsEnvelope> {
    run_ops(
        "/ops/host/services-failed",
        &[
            "systemctl",
            "list-units",
            "--type=service",
            "--state=failed",
            "--no-pager",
        ],
    )
    .await
}

async fn ops_ssh_recent(State(_): State<AppState>) -> Json<OpsEnvelope> {
    run_ops(
        "/ops/host/ssh-recent",
        &[
            "journalctl",
            "-u",
            "ssh",
            "--since",
            "24h",
            "--no-pager",
            "-n",
            "200",
        ],
    )
    .await
}

async fn ops_k8s_nodes(State(_): State<AppState>) -> Json<OpsEnvelope> {
    run_ops("/ops/k8s/nodes", &["kubectl", "get", "nodes", "-o", "json"]).await
}

async fn ops_k8s_pods_not_running(State(_): State<AppState>) -> Json<OpsEnvelope> {
    run_ops(
        "/ops/k8s/pods-not-running",
        &[
            "kubectl",
            "get",
            "pods",
            "-A",
            "--field-selector=status.phase!=Running",
            "-o",
            "json",
        ],
    )
    .await
}

async fn ops_k8s_ingress(State(_): State<AppState>) -> Json<OpsEnvelope> {
    run_ops(
        "/ops/k8s/ingress",
        &["kubectl", "get", "ingress", "-A", "-o", "json"],
    )
    .await
}

async fn ops_k8s_warnings(State(_): State<AppState>) -> Json<OpsEnvelope> {
    run_ops(
        "/ops/k8s/warnings",
        &[
            "kubectl",
            "get",
            "events",
            "-A",
            "--field-selector=type=Warning",
        ],
    )
    .await
}

async fn run_ops(endpoint: &'static str, cmd: &[&str]) -> Json<OpsEnvelope> {
    let collected_at = chrono_now();
    match run_command(cmd).await {
        Ok((code, stdout, stderr)) => Json(OpsEnvelope {
            endpoint,
            collected_at,
            exit_code: code,
            stdout,
            stderr,
        }),
        Err(err) => Json(OpsEnvelope {
            endpoint,
            collected_at,
            exit_code: 1,
            stdout: String::new(),
            stderr: err,
        }),
    }
}

async fn internal_chat(
    State(state): State<AppState>,
    Json(body): Json<ChatRequest>,
) -> Result<Json<ChatResponse>, StatusCode> {
    let (_message, system, user, sources) = prepare_chat(&body)?;
    let reply = ollama_chat(&state.ollama_model, &system, &user)
        .await
        .map_err(|_| StatusCode::BAD_GATEWAY)?;

    Ok(Json(ChatResponse {
        reply,
        model: state.ollama_model.clone(),
        sources,
    }))
}

async fn internal_chat_stream(
    State(state): State<AppState>,
    Json(body): Json<ChatRequest>,
) -> Result<Sse<impl futures_util::Stream<Item = Result<Event, Infallible>>>, StatusCode> {
    let (_message, system, user, sources) = prepare_chat(&body)?;
    let model = state.ollama_model.clone();

    let (tx, rx) = tokio::sync::mpsc::channel::<Result<Event, Infallible>>(256);
    tokio::spawn(async move {
        let send = |event: Event| async { tx.send(Ok(event)).await.is_ok() };

        if !send(Event::default().event("meta").data(
            serde_json::to_string(&json!({ "sources": sources })).unwrap_or_else(|_| "{}".into()),
        ))
        .await
        {
            return;
        }

        match ollama_chat_stream(&model, &system, &user, tx.clone()).await {
            Ok(full) => {
                let _ = send(
                    Event::default().event("done").data(
                        serde_json::to_string(&json!({ "model": model, "reply": full }))
                            .unwrap_or_else(|_| "{}".into()),
                    ),
                )
                .await;
            }
            Err(err) => {
                if let Ok(full) = ollama_chat(&model, &system, &user).await {
                    let _ = send(
                        Event::default()
                            .event("token")
                            .data(json!({ "delta": full }).to_string()),
                    )
                    .await;
                    let _ = send(
                        Event::default().event("done").data(
                            serde_json::to_string(&json!({
                                "model": model,
                                "reply": full,
                                "fallback": true
                            }))
                            .unwrap_or_else(|_| "{}".into()),
                        ),
                    )
                    .await;
                } else {
                    let _ = send(
                        Event::default()
                            .event("error")
                            .data(json!({ "message": err }).to_string()),
                    )
                    .await;
                }
            }
        }
    });

    Ok(Sse::new(ReceiverStream::new(rx))
        .keep_alive(KeepAlive::new().interval(Duration::from_secs(15))))
}

fn prepare_chat(body: &ChatRequest) -> Result<(String, String, String, Vec<String>), StatusCode> {
    let message = body.message.trim();
    if message.is_empty() || message.len() > 4000 {
        return Err(StatusCode::BAD_REQUEST);
    }

    let sources: Vec<String> = body
        .context
        .as_object()
        .map(|o| o.keys().cloned().collect())
        .unwrap_or_default();

    let compact = compact_context_for_llm(&body.context);
    let fleet_manifest = body
        .context
        .get("fleet_manifest")
        .cloned()
        .unwrap_or_else(|| json!({}));
    let fleet_json =
        serde_json::to_string_pretty(&fleet_manifest).unwrap_or_else(|_| "{}".into());
    let system = format!(
        "You are a read-only fleet operations assistant. Answer in Brazilian Portuguese, concisely, in plain text. \
Use ONLY the JSON context provided. If data is missing, say so. Do NOT echo or repeat the context JSON. \
Never suggest destructive commands.\n\n\
Fleet manifest (authoritative inventory — list these hosts when asked about scope):\n{fleet_json}\n\n\
When the operator asks which hosts you cover, which machines, or what you can do, answer from fleet_manifest first. \
If the question targets a specific host, name that host; if ambiguous, list hosts from the manifest and ask for clarification."
    );
    let context_json = serde_json::to_string_pretty(&compact).unwrap_or_else(|_| "{}".into());
    let user = format!("Context JSON:\n{context_json}\n\nQuestion:\n{message}");

    Ok((message.to_string(), system, user, sources))
}

async fn run_command(cmd: &[&str]) -> Result<(i32, String, String), String> {
    let mut command = Command::new(cmd[0]);
    command
        .args(&cmd[1..])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let child = timeout(CMD_TIMEOUT, command.output())
        .await
        .map_err(|_| "command timed out".to_string())?
        .map_err(|e| format!("spawn failed: {e}"))?;
    let code = child.status.code().unwrap_or(1);
    let mut stdout = String::from_utf8_lossy(&child.stdout).into_owned();
    if stdout.len() > 64_000 {
        stdout.truncate(64_000);
        stdout.push_str("\n... [truncated]");
    }
    Ok((
        code,
        stdout,
        String::from_utf8_lossy(&child.stderr).into_owned(),
    ))
}

fn truncate_field(s: &str, max: usize) -> String {
    if s.len() <= max {
        return s.to_string();
    }
    let mut out = s[..max].to_string();
    out.push_str("\n... [truncated]");
    out
}

fn compact_context_for_llm(ctx: &Value) -> Value {
    let Some(obj) = ctx.as_object() else {
        return ctx.clone();
    };
    let mut out = serde_json::Map::new();
    for (key, value) in obj {
        let mut entry = value.clone();
        if let Some(map) = entry.as_object_mut() {
            if let Some(stdout) = map.get("stdout").and_then(|v| v.as_str()) {
                map.insert("stdout".into(), json!(truncate_field(stdout, 800)));
            }
            if let Some(stderr) = map.get("stderr").and_then(|v| v.as_str()) {
                if !stderr.is_empty() {
                    map.insert("stderr".into(), json!(truncate_field(stderr, 300)));
                }
            }
        }
        out.insert(key.clone(), entry);
    }
    Value::Object(out)
}

async fn ollama_chat(model: &str, system: &str, user: &str) -> Result<String, String> {
    let payload = ollama_chat_payload(model, system, user, false);
    let client = ollama_client()?;

    let resp = client
        .post("http://127.0.0.1:11434/api/chat")
        .json(&payload)
        .send()
        .await
        .map_err(|e| format!("ollama request: {e}"))?;

    if !resp.status().is_success() {
        return Err(format!("ollama status: {}", resp.status()));
    }

    let body: Value = resp.json().await.map_err(|e| e.to_string())?;
    body["message"]["content"]
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| "missing message.content".to_string())
}

async fn ollama_chat_stream(
    model: &str,
    system: &str,
    user: &str,
    tx: tokio::sync::mpsc::Sender<Result<Event, Infallible>>,
) -> Result<String, String> {
    let payload = ollama_chat_payload(model, system, user, true);
    let client = ollama_client()?;

    let resp = client
        .post("http://127.0.0.1:11434/api/chat")
        .json(&payload)
        .send()
        .await
        .map_err(|e| format!("ollama request: {e}"))?;

    if !resp.status().is_success() {
        return Err(format!("ollama status: {}", resp.status()));
    }

    let mut full = String::new();
    let mut byte_stream = resp.bytes_stream();
    let mut buffer = String::new();

    while let Some(chunk) = byte_stream.next().await {
        let chunk = match chunk {
            Ok(c) => c,
            Err(e) => {
                if !full.is_empty() {
                    return Ok(full);
                }
                return Err(format!("ollama stream: {e}"));
            }
        };
        buffer.push_str(&String::from_utf8_lossy(&chunk));

        while let Some(pos) = buffer.find('\n') {
            let line = buffer[..pos].trim().to_string();
            buffer.drain(..=pos);
            if line.is_empty() {
                continue;
            }
            let parsed: Value =
                serde_json::from_str(&line).map_err(|e| format!("ollama json: {e}"))?;
            if let Some(delta) = parsed["message"]["content"].as_str() {
                if !delta.is_empty() {
                    full.push_str(delta);
                    let payload = serde_json::to_string(&json!({ "delta": delta }))
                        .unwrap_or_else(|_| "{}".into());
                    if tx
                        .send(Ok(Event::default().event("token").data(payload)))
                        .await
                        .is_err()
                    {
                        return Ok(full);
                    }
                }
            }
            if parsed["done"].as_bool() == Some(true) {
                return Ok(full);
            }
        }
    }

    if !buffer.trim().is_empty() {
        if let Ok(parsed) = serde_json::from_str::<Value>(buffer.trim()) {
            if let Some(delta) = parsed["message"]["content"].as_str() {
                if !delta.is_empty() {
                    full.push_str(delta);
                }
            }
            if parsed["done"].as_bool() == Some(true) {
                return Ok(full);
            }
        }
    }

    if full.is_empty() {
        return Err("ollama stream: empty response".to_string());
    }
    Ok(full)
}

fn chrono_now() -> String {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs().to_string())
        .unwrap_or_else(|_| "0".into())
}
