# agent-meter — OSS Productization Roadmap

**Data**: 2026-06-08
**Status**: Planning → Execution
**Owner**: Copilot/VSCode
**Objetivo**: Transformar o agent-meter de PoC monolítico (Postgres-only, deploy manual) em produto OSS production-ready — instalável, modular, extensível e bem estruturado.

---

## Visão Final

```
┌─────────────────────────────────────────────────────────────────────┐
│                    agent-meter v1.0 (OSS)                            │
│                                                                     │
│  Single binary: `agent-meter serve`                                  │
│  Database: --db postgres://... | --db sqlite:///path/data.db         │
│  Config: agent-meter.toml | env vars | CLI flags                    │
│  Install: cargo install | docker | helm | apt/brew | binary release  │
│                                                                     │
│  Crates:                                                            │
│    agent-meter-core    — domain models, traits, business logic       │
│    agent-meter-db      — Database trait + Postgres + SQLite impls    │
│    agent-meter-server  — Axum HTTP + OTLP server                     │
│    agent-meter-cli     — CLI tool (send events, query reports)        │
│    agent-meter-proxy   — HTTPS proxy (already done)                  │
│    agent-meter-mcp     — MCP wrapper for IDE interception            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Princípios

1. **Single Responsibility** — cada crate faz uma coisa
2. **Dependency Inversion** — services dependem de traits, não de `PgPool`
3. **Open/Closed** — novos backends (MySQL, DuckDB) sem alterar core
4. **Zero-config happy path** — `agent-meter serve` com SQLite embutido funciona sem setup
5. **Production-ready** — Postgres para deploy sério, com migrations automáticas
6. **Cross-platform** — Linux (ARM64/x86_64), macOS (ARM64), Windows (x86_64)
7. **12-Factor** — config via env, stateless server, logs estruturados

---

## Fases de Execução

### Fase 1: Database Abstraction Layer (T-OSS-01)

**Objetivo**: Desacoplar todo SQL direto do `PgPool` e criar trait `Database`.

```rust
// crates/agent-meter-db/src/lib.rs
#[async_trait]
pub trait Database: Send + Sync + 'static {
    // Events
    async fn insert_tool_call(&self, event: &ToolCallRow) -> Result<()>;
    async fn query_events(&self, params: &EventQuery) -> Result<Vec<ToolCallRow>>;

    // Reports
    async fn top_tools(&self, params: &ReportParams) -> Result<Vec<TopToolRow>>;
    async fn top_agents(&self, params: &ReportParams) -> Result<Vec<TopAgentRow>>;
    async fn calls_over_time(&self, params: &TimeSeriesParams) -> Result<Vec<TimePoint>>;

    // Cost
    async fn cost_summary(&self, params: &CostParams) -> Result<CostSummary>;

    // Conversations
    async fn list_conversations(&self, params: &ConvQuery) -> Result<Vec<ConversationRow>>;
    async fn conversation_detail(&self, id: Uuid) -> Result<Vec<ToolCallRow>>;

    // Orgs & Auth
    async fn find_org(&self, id: Uuid) -> Result<Option<OrgRow>>;
    async fn list_api_keys(&self, org_id: Uuid) -> Result<Vec<ApiKeyRow>>;
    async fn create_api_key(&self, org_id: Uuid, name: &str) -> Result<CreatedKey>;
    async fn revoke_api_key(&self, key_id: Uuid) -> Result<()>;
    async fn find_key_by_hash(&self, hash: &str) -> Result<Option<ApiKeyRow>>;

    // Search
    async fn search(&self, query: &str, limit: i64) -> Result<Vec<SearchResult>>;

    // Migrations
    async fn migrate(&self) -> Result<()>;
}
```

**Sub-tasks**:
- [ ] Criar crate `agent-meter-db` com trait `Database`
- [ ] Extrair domain models de services → `agent-meter-core`
- [ ] Implementar `PostgresDb` (mover SQL existente)
- [ ] Implementar `SqliteDb` (mesmo schema, dialeto SQLite)
- [ ] AppState usa `Arc<dyn Database>` em vez de `PgPool`
- [ ] Config: `DATABASE_URL=sqlite:///var/lib/agent-meter/data.db` ou `postgres://...`
- [ ] Migrations embedded (sqlx embed ou refinery)
- [ ] Testes: rodar suite inteira contra ambos backends

**Est**: 8h

---

### Fase 2: Core Domain Extraction (T-OSS-02)

**Objetivo**: Mover modelos, validação e lógica de negócio para `agent-meter-core` (zero I/O).

**Inclui**:
- [ ] Structs: `ToolCall`, `Conversation`, `CostSummary`, `Organization`, `ApiKey`, `Budget`, `Alert`
- [ ] Enums: `BillingModel`, `Ide`, `AlertCondition`, `NotificationChannel`
- [ ] Token estimator (puro, sem I/O)
- [ ] Cost calculator (pricing table in-memory)
- [ ] Validation (event sanitization, field limits)
- [ ] Error types (domain errors vs infra errors)

**Regra**: `agent-meter-core` não depende de axum, sqlx, tokio — apenas serde, chrono, uuid, thiserror.

**Est**: 4h

---

### Fase 3: Server Consolidation (T-OSS-03)

**Objetivo**: `agent-meter-server` é o crate final que monta tudo. Entrypoint unificado.

```bash
agent-meter serve                        # SQLite default em ~/.agent-meter/data.db
agent-meter serve --db postgres://...    # Postgres
agent-meter serve --config ./agent-meter.toml
agent-meter serve --port 8081 --otlp-port 4318
```

**Sub-tasks**:
- [ ] Unificar `main.rs` → clap com subcommands (`serve`, `migrate`, `version`)
- [ ] Config cascade: CLI flags > env vars > TOML file > defaults
- [ ] Criar `agent-meter.toml` schema
- [ ] Health endpoint retorna db backend + version + uptime
- [ ] Graceful shutdown com drain de conexões
- [ ] `--embedded-ui` flag (default: true) — serve UI estática

**Est**: 4h

---

### Fase 4: SQLite Backend Complete (T-OSS-04)

**Objetivo**: SQLite funcional para single-user/solo deploy.

**Diferenças vs Postgres**:
- Sem `jsonb` → JSON como TEXT com funções json_extract
- Sem `ILIKE` → `LIKE` case-insensitive via COLLATE NOCASE
- Sem `timestamptz` → TEXT ISO8601
- Sem `uuid` type → TEXT com CHECK
- Sem GIN index → FTS5 para search
- WAL mode obrigatório para concorrência
- `PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;`

**Sub-tasks**:
- [ ] Schema SQLite equivalente (todas as tabelas)
- [ ] FTS5 virtual table para search
- [ ] Migrations embedded (up/down)
- [ ] Benchmark: 10k inserts, queries P95
- [ ] Testes integração idênticos ao Postgres

**Est**: 6h

---

### Fase 5: Distribution & Install (T-OSS-05)

**Objetivo**: Binário disponível para todas plataformas sem dependência de cargo.

**Install paths**:
```bash
# Binary releases (GitHub Releases)
curl -sSL https://install.agent-meter.com | sh

# Homebrew (macOS/Linux)
brew install toolhq/tap/agent-meter

# Docker
docker run -p 8081:8081 -v data:/data ghcr.io/toolhq/agent-meter:latest

# Helm (Kubernetes)
helm install agent-meter toolhq/agent-meter --set db.type=postgres --set db.url=...

# Cargo
cargo install agent-meter

# Docker Compose (dev)
docker compose up
```

**Sub-tasks**:
- [ ] GitHub Actions: cross-compile (linux-x86_64, linux-arm64, darwin-arm64, windows-x86_64)
- [ ] Release workflow: tag → build → upload binaries → publish crates.io
- [ ] Dockerfile multi-stage (slim runtime)
- [ ] Helm chart em `charts/agent-meter/`
- [ ] Install script (`install.sh`)
- [ ] `docker-compose.yml` standalone (SQLite mode)
- [ ] `docker-compose.postgres.yml` (Postgres mode)

**Est**: 6h

---

### Fase 6: Configuration & DX (T-OSS-06)

**Objetivo**: Experiência de 60 segundos → first event.

**`agent-meter.toml`**:
```toml
[server]
host = "0.0.0.0"
port = 8081
otlp_port = 4318

[database]
url = "sqlite:///var/lib/agent-meter/data.db"
# url = "postgres://user:pass@localhost/agent_meter"
max_connections = 10

[auth]
require_api_key = false
github_client_id = ""
github_client_secret = ""

[telemetry]
log_level = "info"
log_format = "json"  # or "pretty"
otel_endpoint = ""   # optional: export own traces

[pricing]
auto_update = true
update_interval = "24h"

[ui]
embedded = true
theme = "dark"
```

**Sub-tasks**:
- [ ] Config parsing: TOML + env overlay + CLI override
- [ ] `agent-meter init` → gera `agent-meter.toml` interativo
- [ ] `agent-meter check` → valida config + testa DB connection
- [ ] Documentação: getting-started.md (3 caminhos: binary, Docker, K8s)

**Est**: 3h

---

### Fase 7: Code Quality & SOLID Pass (T-OSS-07)

**Objetivo**: Refatorar services para clean architecture.

**Atual** (anti-patterns):
- Services recebem `&PgPool` diretamente
- Lógica de negócio misturada com SQL
- Route handlers fazem I/O + lógica + formatação
- Sem testes unitários (apenas integração implícita)

**Target**:
- Route handlers: parse request → call service → format response
- Services: business logic pura, recebe `&dyn Database`
- Database: query execution isolada
- Error handling: domain errors ↔ HTTP errors mapeados na borda

**Sub-tasks**:
- [ ] Refatorar `event_service.rs`: separar validação → persistência
- [ ] Refatorar `cost_service.rs`: pricing calc pura + queries separadas
- [ ] Refatorar `report_service.rs`: composição de queries
- [ ] Refatorar `conversation_service.rs`
- [ ] Refatorar `search_service.rs`
- [ ] Extrair middlewares em módulo próprio com testes
- [ ] Adicionar `#[cfg(test)]` unitários em cada service (mock db)
- [ ] Clippy pedantic + rustfmt enforced
- [ ] Doc comments nos tipos públicos

**Est**: 10h

---

### Fase 8: Testing & CI (T-OSS-08)

**Objetivo**: Suite de testes confiável para OSS contributions.

**Sub-tasks**:
- [ ] Unit tests: core (token estimator, cost calc, validation)
- [ ] Integration tests: PostgresDb + SqliteDb (testcontainers ou tempfile)
- [ ] API tests: full request/response (axum test helpers)
- [ ] CI matrix: `{postgres, sqlite}` × `{linux-arm64, linux-x86_64}`
- [ ] Coverage badge (>70%)
- [ ] `cargo deny` (license audit)
- [ ] `cargo audit` (security)
- [ ] Benchmarks (criterion): ingest throughput, query P95

**Est**: 6h

---

### Fase 9: Documentation & Community (T-OSS-09)

**Objetivo**: Repo standalone pronto para estrelas no GitHub.

**Sub-tasks**:
- [ ] README.md com hero, quickstart, screenshots
- [ ] CONTRIBUTING.md
- [ ] Architecture docs (`docs/architecture.md`)
- [ ] API reference (auto-generated from routes or manual OpenAPI)
- [ ] Changelog (keep-a-changelog)
- [ ] LICENSE (MIT)
- [ ] Issue templates
- [ ] `docs/` site (mdbook ou similar)

**Est**: 4h

---

## Resumo de Estimativas

| Fase | Task ID | Título | Est. |
|------|---------|--------|------|
| 1 | T-OSS-01 | Database Abstraction Layer | 8h |
| 2 | T-OSS-02 | Core Domain Extraction | 4h |
| 3 | T-OSS-03 | Server Consolidation | 4h |
| 4 | T-OSS-04 | SQLite Backend Complete | 6h |
| 5 | T-OSS-05 | Distribution & Install | 6h |
| 6 | T-OSS-06 | Configuration & DX | 3h |
| 7 | T-OSS-07 | Code Quality & SOLID Pass | 10h |
| 8 | T-OSS-08 | Testing & CI | 6h |
| 9 | T-OSS-09 | Documentation & Community | 4h |
| | | **TOTAL** | **51h** |

**Timeline realista**: ~2.5 semanas full-time, ~5 semanas meio-período.

---

## Ordem de Execução Recomendada

```
T-OSS-02 (core extraction) ─→ T-OSS-01 (db trait) ─→ T-OSS-04 (sqlite)
                                      ↓
                                T-OSS-07 (SOLID pass)
                                      ↓
                                T-OSS-03 (server consolidation)
                                      ↓
                              T-OSS-06 (config/DX)
                                      ↓
                              T-OSS-05 (distribution)
                                      ↓
                              T-OSS-08 (testing/CI)
                                      ↓
                              T-OSS-09 (docs/community)
```

---

## Dependências com Backlog SaaS

| OSS Task | Depende de | Bloqueia |
|----------|-----------|----------|
| T-OSS-01 | — | T-OSS-03, T-OSS-04 |
| T-OSS-04 | T-OSS-01 | T-OSS-05 (Docker SQLite mode) |
| T-OSS-05 | T-OSS-03 | Publicação crates.io |
| T-OSS-07 | T-OSS-02 | Code quality para PR externo |

O trabalho OSS é **paralelo** ao SaaS backlog (T-323 Quickstart, T-322 Hosted Infra, T-324 UX).
A ordem sugerida: **primeiro fechar o SaaS critical path** (T-323 → T-322), depois atacar OSS.

---

## Decisões Técnicas Pendentes

| # | Decisão | Opções | Preferência |
|---|---------|--------|-------------|
| 1 | Migration engine | sqlx-migrate embedded / refinery / manual | refinery (suporta Pg+SQLite) |
| 2 | Config format | TOML / YAML / env-only | TOML + env overlay |
| 3 | Repo split | Monorepo (aqui) / Standalone repo | Standalone `github.com/ToolHQ/agent-meter` |
| 4 | Naming | `agent-meter` / `agentmeter` / `ameter` | `agent-meter` |
| 5 | Min Rust version | stable / MSRV 1.75 | MSRV 1.80 (async traits estáveis) |
| 6 | License | MIT / Apache-2.0 / dual | MIT |
