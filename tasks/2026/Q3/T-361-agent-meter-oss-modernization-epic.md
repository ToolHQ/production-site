# T-361 — agent-meter OSS Modernization Epic

> **Objetivo**: Transformar o agent-meter num projeto Rust standalone, modular,
> SOLID, pronto para open-source — rodável em K8s, Docker, bare-metal, e com DB
> backend trocável (Postgres ↔ SQLite).

**Owner**: Copilot/VSCode  
**Priority**: 🚨 Critical (próxima prioridade após bug fixes)  
**Est. Total**: ~8-10d

---

## Estado Atual (8.4k LOC, 4 crates)

```
agent-meter/
├── crates/collector/   (core: routes, services, models, middleware, otlp)
├── crates/cli/         (CLI admin — 440 LOC)
├── crates/mcp-wrapper/ (MCP stdio proxy)
├── crates/proxy/       (MITM proxy — intercepta OTLP)
└── migrations/         (SQL postgres-only)
```

### Problemas Identificados

1. **DB coupling**: `PgPool` hardcoded em todos services; queries raw SQL Postgres-only
2. **Sem abstração de storage**: nenhum trait/interface — impossível trocar DB
3. **Config monolítica**: tudo via env vars, sem suporte a config file
4. **Sem modo standalone**: requer Postgres externo obrigatoriamente
5. **Deploy acoplado**: manifests K8s dentro do app; sem Dockerfile multi-stage clean
6. **UI embutida**: HTML via `include_str!` — funcional mas não modular
7. **Sem testes de integração**: apenas 2 test files (api.rs, otlp_regression.rs)
8. **Services monolíticos**: cost_service.rs, event_service.rs fazem demais (query + business logic + formatting)

---

## Fases de Execução

### Fase 1 — Repository Trait + DB Abstraction (T-362 a T-365)

Criar trait `Repository` que abstrai o storage. Implementar para Postgres e SQLite.

| Sub-task | Descrição | Est. |
|----------|-----------|------|
| T-362 | **Repository trait definition** — `trait EventRepo`, `trait CostRepo`, `trait OrgRepo`, `trait AlertRepo` com async methods genéricos | 3h |
| T-363 | **Postgres implementation** — mover queries existentes para `impl EventRepo for PgRepo` etc. Zero mudança de comportamento. | 4h |
| T-364 | **SQLite implementation** — `impl EventRepo for SqliteRepo`; adaptar SQL dialect; migrations SQLite separadas | 6h |
| T-365 | **Runtime DB selection** — `DATABASE_URL` prefix determina backend (`postgres://` vs `sqlite://` vs `file:`); feature flags no Cargo.toml | 2h |

### Fase 2 — SOLID Refactor + Service Layer (T-366 a T-369)

| Sub-task | Descrição | Est. |
|----------|-----------|------|
| T-366 | **Service trait extraction** — cada service vira trait + impl; DI via `Arc<dyn Service>` no AppState | 4h |
| T-367 | **Config modernization** — suporte a `agent-meter.toml` (TOML) + env vars + CLI flags (clap); precedência: CLI > env > file > defaults | 3h |
| T-368 | **Error handling unification** — `thiserror` enum hierárquico por domínio; remover `anyhow` do core; error mapping consistente para HTTP | 2h |
| T-369 | **Module reorganization** — separar `domain/` (models + business rules puras), `infra/` (DB, HTTP, OTLP), `application/` (services/use-cases) | 4h |

### Fase 3 — Single Binary + Packaging (T-370 a T-373)

| Sub-task | Descrição | Est. |
|----------|-----------|------|
| T-370 | **Unified binary** — subcommands: `agent-meter serve`, `agent-meter migrate`, `agent-meter cli`, `agent-meter mcp-wrap` (unificar 4 crates em 1 binary com feature flags) | 6h |
| T-371 | **Embedded migrations** — `sqlx::migrate!()` ou `refinery` embedded; auto-migrate on startup com `--auto-migrate` flag | 2h |
| T-372 | **Dockerfile multi-stage clean** — builder stage (cargo-chef) + runtime (distroless/scratch); suportar `--target=sqlite` sem Postgres | 3h |
| T-373 | **Install script + release binaries** — GitHub Releases com binários pré-compilados (linux-amd64, linux-arm64, macos-arm64); `curl -sSL | sh` installer | 4h |

### Fase 4 — OSS Distribution (T-374 a T-377)

| Sub-task | Descrição | Est. |
|----------|-----------|------|
| T-374 | **docker-compose.yml standalone** — `docker compose up` levanta agent-meter + Postgres (ou SQLite mode); zero config para dev | 2h |
| T-375 | **Helm chart** — chart K8s com values.yaml (DB backend, replicas, ingress, resources); suporta tanto sqlite sidecar quanto external Postgres | 4h |
| T-376 | **README + docs OSS** — quickstart (30s to first event); architecture diagram; API reference; contributing guide | 3h |
| T-377 | **CI/CD pipeline** — GitHub Actions: test matrix (postgres + sqlite), clippy, build multi-arch, release automation, CHANGELOG | 3h |

### Fase 5 — Quality & Polish (T-378 a T-380)

| Sub-task | Descrição | Est. |
|----------|-----------|------|
| T-378 | **Integration test suite** — testes contra Postgres + SQLite; fixtures; test containers (testcontainers-rs) | 6h |
| T-379 | **Clippy strict + deny warnings** — `#![deny(clippy::all)]`, resolve todos os warnings; `cargo fmt --check` no CI | 2h |
| T-380 | **Benchmarks + profiling** — criterion benchmarks para hot paths (event ingestion, cost computation); memory profiling | 3h |

---

## Arquitetura Target

```
agent-meter (single binary)
├── domain/
│   ├── models/         (Event, Conversation, Cost, Alert, Org — pure structs)
│   ├── services/       (business logic traits — zero I/O)
│   └── value_objects/  (BillingModel, TokenCount, UsdAmount)
├── application/
│   ├── commands/       (IngestEvent, ComputeCost, CreateAlert)
│   └── queries/        (GetCostSummary, SearchEvents, ListConversations)
├── infrastructure/
│   ├── db/
│   │   ├── postgres/   (PgRepo impls + migrations)
│   │   └── sqlite/     (SqliteRepo impls + migrations)
│   ├── http/           (Axum routes — thin controllers)
│   ├── otlp/           (OTLP ingest adapter)
│   └── config/         (TOML + env + CLI)
├── ui/                 (static HTML/JS — embedded or served from disk)
└── main.rs             (composition root — wires everything)
```

## Regras de Design

1. **Zero `PgPool` fora de `infrastructure/db/`** — services recebem `Arc<dyn Repo>`
2. **Domain puro** — sem dependência de framework (axum, sqlx, tokio) no domain/
3. **Feature flags** — `postgres` (default), `sqlite`, `ui-embedded`, `otlp`, `stripe`
4. **Config-first** — tudo configurável via TOML; env vars como override
5. **Graceful degradation** — sem Stripe? billing desabilitado. Sem OTLP? log only.
6. **12-factor** — stateless process; config via env; logs para stdout; port binding

## Prioridade de Execução

```
Fase 1 (DB abstraction) → fundação para tudo mais
Fase 2 (SOLID refactor) → qualidade de código
Fase 3 (single binary)  → distribuição standalone
Fase 4 (OSS packaging)  → acessibilidade
Fase 5 (quality)        → confiança para produção
```

## Dependências

- Fase 1 não bloqueia produção (refactor incremental, backward-compatible)
- Fase 3 depende de Fase 1 (precisa do SQLite impl para standalone)
- Fase 4 depende de Fase 3 (precisa do binary unificado)
- Fase 5 pode começar em paralelo com Fase 3/4
