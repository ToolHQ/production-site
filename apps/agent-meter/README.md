# agent-meter

Observabilidade e FinOps para workflows de desenvolvimento com agentes de IA.

Captura tool calls, tokens estimados, custo, latência e erros de **VS Code Copilot, Eclipse Copilot, Cursor, OpenCode, Antigravity** e qualquer agente customizado.

## Configuração de captura por IDE

→ **[docs/capture-setup.md](docs/capture-setup.md)** — guia completo com matriz de compatibilidade, procedimentos de instalação e troubleshooting para cada IDE.

| IDE | Método | Comando |
|-----|--------|---------|
| VS Code | OTLP nativo | `settings.json` — 2 linhas |
| Eclipse | mitmproxy proxy | `eclipse-proxy/start_proxy.sh --setup` |
| Cursor | mitmproxy proxy | `cursor-proxy/start_proxy.sh --setup` → `cursor-metered .` |
| OpenCode / outros | REST direto | env `AGENT_METER_COLLECTOR_URL` |

## Quick start (desenvolvimento local)

```bash
# Start PostgreSQL
docker compose up -d postgres

# Run migrations
cargo sqlx migrate run

# Start collector
cargo run -p collector
```

## Send a test event

```bash
curl -X POST http://localhost:8081/events/tool-call \
  -H "Content-Type: application/json" \
  -d '{
    "tool_name": "read_file",
    "mcp_server": "filesystem",
    "started_at": "2026-05-17T12:00:00Z",
    "ended_at": "2026-05-17T12:00:01Z",
    "ok": true,
    "request_bytes": 1200,
    "response_bytes": 30000
  }'
```

## Reports

```bash
curl http://localhost:8081/reports/top-tools
curl http://localhost:8081/reports/top-tasks
curl http://localhost:8081/reports/top-mcp-servers
```

## Deploy

```bash
./deploy.sh
```

## Project structure

```
apps/agent-meter/
├── crates/collector/   # HTTP collector API (Axum)
├── crates/cli/          # CLI client (WIP)
├── crates/mcp-wrapper/  # MCP wrapper proxy (WIP)
├── migrations/          # SQLx migrations
├── docker-compose.yml   # Local dev
├── Dockerfile           # ARM64 build
└── deploy.sh            # OCI cluster deploy
```

## Security

- No full prompts or responses stored by default
- Only SHA-256 hashes, byte sizes, and metadata
- No secrets in metadata
- Local-first by design
