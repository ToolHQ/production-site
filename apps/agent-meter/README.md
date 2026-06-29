# agent-meter

**Observability and FinOps for AI-powered development workflows.**

Track every LLM call, tool invocation, and token spent across all your IDEs and AI agents — in one self-hosted dashboard.

<p align="center">
  <img src="docs/assets/screenshot-dashboard.png" alt="agent-meter dashboard" width="700">
</p>

---

## Why agent-meter?

AI coding assistants are powerful but opaque. Teams using multiple IDEs and agents have no unified view of:

- **How much** they're spending on LLM tokens (per model, per day, per developer)
- **Which tools** are being called most frequently (and which are failing)
- **What models** are being used across different agents
- **How long** AI interactions take end-to-end

agent-meter solves this with a lightweight, self-hosted collector that aggregates telemetry from every IDE and CLI tool in your workflow.

---

## Supported IDEs & Tools

| IDE / Tool | Capture Method | Setup | Data Quality |
|------------|---------------|-------|:------------:|
| **VS Code** (GitHub Copilot) | OTLP Native | 2 lines in `settings.json` | ★★★★★ |
| **Cursor** | HTTPS Proxy | `cursor-metered .` | ★★★★☆ |
| **Eclipse** (GitHub Copilot) | HTTPS Proxy | `./start_proxy.sh --setup` | ★★★★☆ |
| **Copilot CLI** (`gh copilot`) | HTTPS Proxy | Wrapper script | ★★★★☆ |
| **Claude Code** (Anthropic CLI) | HTTPS Proxy | Env vars | ★★★★☆ |
| **Codex CLI** (OpenAI) | HTTPS Proxy | Env vars | ★★★★☆ |
| **OpenCode** | REST Direct | Env vars | ★★★★★ |
| **Antigravity** | REST Direct | Env vars | ★★★★★ |
| Custom agents | REST Direct | `POST /events/tool-call` | ★★★★★ |

> **The proxy approach is fully agnostic.** Any CLI or IDE that makes HTTPS calls to AI APIs (Anthropic, OpenAI, GitHub Copilot) is captured automatically — no per-tool plugin required.

→ **[Full setup guide](docs/capture-setup.md)** — per-IDE configuration, troubleshooting, and architecture details.

---

## Quick Start

### Docker Compose (recommended)

```bash
git clone https://github.com/ToolHQ/production-site.git
cd production-site/apps/agent-meter

# Start PostgreSQL + collector
docker compose up -d

# Collector is now listening:
#   :3000  — Web UI + REST API
#   :4318  — OTLP receiver (VS Code)
```

### From Source

```bash
# Prerequisites: Rust 1.75+, PostgreSQL 15+
cargo install sqlx-cli

export DATABASE_URL="postgres://localhost/agent_meter"
sqlx database create && sqlx migrate run

cargo run -p collector
# → http://localhost:3000
```

### First Telemetry in 60 Seconds

1. Start the collector (above)
2. Add to VS Code `settings.json`:
   ```json
   {
     "github.copilot.chat.otel.enabled": true,
     "github.copilot.chat.otel.otlpEndpoint": "http://localhost:4318"
   }
   ```
3. Start a Copilot chat → data appears on the dashboard immediately.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      DATA SOURCES                                 │
├─────────────┬────────────────┬────────────────┬─────────────────┤
│  VS Code    │  Cursor/Eclipse│  CLI Tools     │  Custom Agents  │
│  (OTLP)    │  (mitmproxy)   │  (mitmproxy)   │  (REST API)     │
│  :4318      │  :8898/:8899   │  :8898/:8899   │  :3000          │
└──────┬──────┴───────┬────────┴───────┬────────┴────────┬────────┘
       │              │                │                 │
       ▼              ▼                ▼                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                   agent-meter collector                           │
│                                                                  │
│  OTLP Receiver → IDE Detection → Conversation Grouping → Cost   │
│                                                                  │
│  PostgreSQL ←─── Events / Conversations / Cost / Alerts          │
│                                                                  │
│  Web UI: Dashboard · Conversations · Cost · Alerts · Reports     │
└─────────────────────────────────────────────────────────────────┘
```

Three capture methods:

1. **OTLP Native** — VS Code sends OpenTelemetry spans directly (zero overhead)
2. **HTTPS Proxy** — mitmproxy intercepts AI API traffic for Cursor, Eclipse, and CLIs
3. **REST Direct** — Agents post events via `curl` / HTTP client

---

## CLI Support

The HTTPS proxy technique is **transport-level** — it intercepts HTTP requests regardless of whether they come from a GUI IDE or a terminal CLI. This means:

| CLI Tool | API Endpoint | Works with Proxy? |
|----------|-------------|:-----------------:|
| `gh copilot suggest/explain` | api.githubcopilot.com | ✅ |
| `claude` (Anthropic CLI) | api.anthropic.com | ✅ |
| `codex` (OpenAI CLI) | api.openai.com | ✅ |
| Any HTTPS-based AI CLI | Any AI API | ✅ |

**Setup is identical**: set `HTTPS_PROXY=http://127.0.0.1:8898` and `SSL_CERT_FILE=~/.mitmproxy/mitmproxy-ca-cert.pem`.

A dedicated wrapper exists for Copilot CLI:

```bash
# Metered Copilot CLI (auto-configures proxy)
./eclipse-proxy/copilot-cli-metered.sh suggest "how to list k8s pods"
```

---

## API Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/events/tool-call` | Ingest a tool call event |
| `GET` | `/api/conversations` | List conversations (paginated) |
| `GET` | `/api/conversations/:id` | Conversation detail |
| `GET` | `/api/conversations/:id/timeline` | Span waterfall |
| `GET` | `/reports/top-tools` | Most-used tools |
| `GET` | `/reports/top-tasks` | Top tasks by activity |
| `GET` | `/reports/top-mcp-servers` | Most active MCP servers |
| `GET` | `/reports/cost-daily` | Daily cost breakdown |
| `GET` | `/reports/cost-by-model` | Cost by model |
| `GET` | `/health` | Health check |

### Example: Send a Tool Call Event

```bash
curl -X POST http://localhost:3000/events/tool-call \
  -H "Content-Type: application/json" \
  -d '{
    "tool_name": "read_file",
    "mcp_server": "filesystem",
    "started_at": "2026-01-15T10:00:00Z",
    "ended_at": "2026-01-15T10:00:01Z",
    "ok": true,
    "request_bytes": 1200,
    "response_bytes": 30000
  }'
```

---

## Project Structure

```
apps/agent-meter/
├── crates/
│   ├── collector/          # Axum HTTP server (REST API + OTLP + Web UI)
│   │   ├── src/
│   │   │   ├── routes/     # API endpoints
│   │   │   ├── otlp/       # OTLP receiver + IDE detection
│   │   │   └── services/   # Business logic (conversations, cost)
│   │   └── ui/             # HTML pages (design system)
│   ├── cli/                # CLI client (WIP)
│   └── mcp-wrapper/        # MCP wrapper proxy (WIP)
├── cursor-proxy/           # mitmproxy addon for Cursor + Claude Code + Codex CLI
├── eclipse-proxy/          # mitmproxy addon for Eclipse + Copilot CLI
├── migrations/             # SQLx PostgreSQL migrations
├── docs/                   # Extended documentation
├── docker-compose.yml      # Local development stack
├── Dockerfile              # Multi-stage ARM64 build
└── deploy.sh               # Kubernetes deployment script
```

---

## Security & Privacy

| Concern | Approach |
|---------|----------|
| **Prompt content** | Not stored by default. Opt-in via `captureContent: true` |
| **Auth tokens** | Never stored. Only a prefix hash for session grouping |
| **Network exposure** | Proxy listens on `127.0.0.1` only. All data stays local |
| **CA certificates** | Unique per installation. Removable at any time |
| **Data residency** | Self-hosted. No external telemetry or phone-home |

---

## Documentation

- **[Capture Setup Guide](docs/capture-setup.md)** — Per-IDE installation and troubleshooting
- **[OTEL Integration](docs/agent-meter-otel.md)** — OpenTelemetry protocol details
- **[WSL Setup](docs/agent-meter-wsl-vscode.md)** — Windows Subsystem for Linux configuration
- **In-app docs** — Available at `/docs` in the Web UI

---

## Deploy

```bash
# Kubernetes (ARM64 cluster)
./deploy.sh

# Requires: Docker buildx, registry access, KUBECONFIG
```

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/my-feature`
3. Run tests: `cargo test`
4. Submit a Pull Request

---

## License

MIT
