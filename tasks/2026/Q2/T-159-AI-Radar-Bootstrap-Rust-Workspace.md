# T-159: AI Radar — Bootstrap Rust Workspace

- **Status**: In Progress
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp
- **Estimation**: 1d
- **Opened**: 2026-05-01

## Context

Primeiro épico do programa **AI Radar** (Decision Engine de curadoria contínua de ferramentas de IA). Cria a fundação Rust no monorepo (`apps/ai-radar/`) com workspace Cargo, 3 crates (`core`/`api`/`cli`), Axum mínimo respondendo `/health`, tracing JSON, configuração via env, Dockerfile multi-stage ARM64+amd64 (distroless), docker-compose com Postgres local e README de onboarding.

Sem este épico, nenhum outro pode começar. Foco em ser pequeno, testável e reproduzível.

Decisões transversais (LLM, schema banco, schedules, budget de recursos) estão documentadas em `docs/AI-RADAR-DECISIONS.md`. Visão de produto em `docs/AI-RADAR-ROADMAP.md`.

## Tasks

- [ ] Criar workspace Cargo em `apps/ai-radar/` (`Cargo.toml` + `rust-toolchain.toml` pinando `1.83.0`)
- [ ] Scaffold dos 3 crates: `crates/ai-radar-core` (lib), `crates/ai-radar-api` (bin), `crates/ai-radar-cli` (bin)
- [ ] Centralizar versões em `[workspace.dependencies]` (axum 0.7, tokio, sqlx 0.8 com `rustls`, reqwest, serde, tracing, tracing-subscriber, anyhow, thiserror, clap, figment, uuid, chrono)
- [ ] Implementar `GET /health` em `ai-radar-api` retornando `{"status":"ok"}` com graceful shutdown em SIGTERM/SIGINT
- [ ] Implementar `init_tracing()` com formatter JSON + `EnvFilter` (`AI_RADAR_LOG_LEVEL`/`RUST_LOG`)
- [ ] Implementar middleware Axum de `request_id` (header `X-Request-Id` + span)
- [ ] Implementar `AppConfig` (figment) lendo env + `.env` em dev, com `.env.example` documentado
- [ ] Criar `docker/Dockerfile.api` e `docker/Dockerfile.cli` multi-stage (builder `rust:1.83-slim` → runtime `gcr.io/distroless/cc-debian12:nonroot`)
- [ ] Criar `docker-compose.yaml` com Postgres 16-alpine + api dev (volume nomeado, healthcheck `pg_isready`)
- [ ] Criar `justfile` com targets `build`, `test`, `lint`, `fmt`, `compose-up`, `compose-down`, `migrate`, `cli`
- [ ] Criar `apps/ai-radar/README.md` cobrindo visão, requisitos, run local, env vars, troubleshooting
- [ ] Criar `apps/ai-radar/.gitignore` (target/, .env)

## DoD

- `cd apps/ai-radar && cargo build --workspace` passa.
- `cargo test --workspace` passa.
- `cargo clippy --workspace -- -D warnings` passa.
- `cargo run -p ai-radar-api` sobe e `curl localhost:8080/health` retorna 200 com JSON.
- Logs saem em JSON com `request_id` quando dentro de request.
- `docker buildx build --platform linux/arm64,linux/amd64 -f docker/Dockerfile.api -t ai-radar-api:dev .` produz imagem <80MB.
- `docker compose up -d` sobe Postgres + API; ambos passam healthcheck.
- README permite onboarding em <5min.

## Validação

```bash
cd apps/ai-radar
cargo build --workspace
cargo test --workspace
cargo clippy --workspace -- -D warnings
cargo fmt --check
docker compose up -d
curl -fsS localhost:8080/health | jq
docker compose logs api | head -20  # validar JSON
docker compose down -v
```

## References

- `docs/AI-RADAR-DECISIONS.md` — arquitetura, stack, budget de recursos
- `docs/AI-RADAR-ROADMAP.md` — super prompt original (Fase 1)
- `AGENTS.md` — GitFlow obrigatório
- Branch sugerida: `feat/T-159-ai-radar-bootstrap-workspace`
