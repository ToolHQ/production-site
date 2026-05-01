# AI Radar

> Self-hosted **Decision Engine** that monitors, deduplicates, structures,
> scores and recommends AI tooling/content with actionable verdicts:
> `adopt | test | monitor | ignore`.

This crate is the Rust workspace that backs the whole AI Radar program. It is
designed to run on a **resource-constrained ARM64 Kubernetes cluster** (1 vCPU
/ 6 GB RAM per node) and to operate **without any mandatory SaaS dependency**.

The full product vision lives in [`docs/AI-RADAR-ROADMAP.md`](../../docs/AI-RADAR-ROADMAP.md)
and the architecture decisions consulted by every epic in
[`docs/AI-RADAR-DECISIONS.md`](../../docs/AI-RADAR-DECISIONS.md). Tasks are tracked in
[`tasks/KANBAN.md`](../../tasks/KANBAN.md) under the IDs `T-159..T-174`.

## Status

Bootstrap ([`T-159`](../../tasks/2026/Q2/T-159-AI-Radar-Bootstrap-Rust-Workspace.md))
plus **database layer and HTTP `/sources`** ([`T-160`](../../tasks/2026/Q2/T-160-AI-Radar-Banco-e-Modelo-de-Dados.md))
are implemented today. **`T-174`** manifests live under **`k8s/`** (`kubectl
kustomize`, overlay `production`, `deploy.sh` arm64+Nexus).
**CronJobs** and the full scheduled demo continue in
[`T-171`](../../tasks/2026/Q2/T-171-AI-Radar-Kubernetes-Operacao-Leve.md). The
remaining product pipeline (RSS/GitHub/web, LLM, extract, score, digest)
spans **T-161..T-173** alongside that infra track.

## Architecture in one diagram

```
┌────────────┐   ┌────────────┐   ┌────────────┐   ┌────────────┐
│  Collector │──▶│ Extractor  │──▶│  Scorer    │──▶│  Digest    │
│ (RSS, GH,  │   │ (LLM JSON) │   │ (rules ±   │   │ (Markdown  │
│  webpages) │   │            │   │ optional   │   │ daily/wkly)│
└────────────┘   └────────────┘   │ LLM merge) │   └────────────┘
       ▲                          └────────────┘          │
       │                                                  │
       │           ┌──────────────┐                       │
       └───────────│  Postgres    │◀──────────────────────┘
                   │  schema      │
                   │  ai_radar    │
                   └──────────────┘
```

CronJobs drive each stage on schedule; the API exposes inspection, manual
runs and feedback. See `docs/AI-RADAR-DECISIONS.md` for resource budgets,
schedules and the full data model.

## Workspace layout

```
apps/ai-radar/
├── Cargo.toml                  # Cargo workspace + [workspace.dependencies]
├── rust-toolchain.toml         # Pinned to 1.88.0
├── deploy.sh                   # ARM64 push to Nexus + kubectl apply (Kustomize)
├── crates/
│   ├── ai-radar-core/          # lib: domain, config, telemetry, repos, providers
│   ├── ai-radar-api/           # bin: Axum HTTP server
│   └── ai-radar-cli/           # bin: clap CLI for CronJobs
├── docker/
│   ├── Dockerfile.api          # distroless multi-stage, multi-arch
│   └── Dockerfile.cli
├── k8s/
│   ├── base/                   # Namespace, SA, ConfigMap, Secret template, Deploy, Service
│   └── overlays/production/    # Tag/latest wiring for oci-builder images
├── docker-compose.yaml         # Postgres + api for local development
├── justfile                    # `just --list` for the DX targets
├── .env.example                # Documented environment variables
└── README.md
```

## Requirements

- **Rust 1.88.0** (or newer). `rust-toolchain.toml` will trigger a download
  via rustup automatically.
- **Docker** + `docker compose` (only for the local stack and image builds).
- **just** (optional but recommended): `cargo install just` or your package
  manager.

The repository-level harness (`tools/harness/verify.sh`) has a dedicated
`rust-ai-radar` gate that runs `cargo fmt --check`, `cargo clippy --workspace
--all-targets -- -D warnings` and `cargo test --workspace`.

## Run locally

### Native (recommended for tight loop)

```sh
cd apps/ai-radar
cargo run -p ai-radar-api
# in another shell
curl -fsS -H 'X-Request-Id: dev-001' http://localhost:8080/health
```

The API binds to `AI_RADAR_API_BIND` (default `0.0.0.0:8080`). Logs are
JSON-formatted and include `request_id` when emitted from inside a request
span.

Override the log level with either:

```sh
AI_RADAR_LOG_LEVEL=debug cargo run -p ai-radar-api
RUST_LOG="ai_radar=trace,info" cargo run -p ai-radar-api
```

### Compose stack (Postgres + API)

```sh
cp .env.example .env  # then edit secrets if you have any
just compose-up        # docker compose up -d --build
just compose-smoke     # waits for /health and prints the response
just compose-logs      # tail JSON logs
just compose-down      # stop and drop volumes
```

By default the API runs in **deterministic-only mode** (`LLM_ENABLED=false`).
Set `LLM_ENABLED=true`, `LLM_API_KEY` and `LLM_MODEL` in `.env` once
[`T-164`](../../tasks/2026/Q2/T-164-AI-Radar-LLM-Provider-Abstraction.md) lands.

## CLI

```sh
cargo run -p ai-radar-cli -- --help
```

Subcommands (`collect`, `extract`, `score`, `digest`, `compare`, `reprocess`,
`run-all`) arrive in subsequent epics. The CLI image
(`docker/Dockerfile.cli`) is the entrypoint used by the Kubernetes CronJobs.

## Configuration

All variables are documented in [`.env.example`](.env.example). The loader
reads them via `figment` from the process environment (`.env` is loaded
automatically in debug builds). Secrets are intentionally `Option<String>` so
the deterministic-only path keeps working when only a subset is supplied.

| Variable | Default | Notes |
|---|---|---|
| `AI_RADAR_API_BIND` | `0.0.0.0:8080` | HTTP listener address |
| `AI_RADAR_LOG_LEVEL` | `info` | Tracing filter; overridden by `RUST_LOG` |
| `DATABASE_URL` | _unset_ | `postgres://...?options=-csearch_path%3Dpublic` (see notes below) |
| `LLM_ENABLED` | `false` | Must be `true` to call the LLM provider |
| `LLM_BASE_URL` | `https://openrouter.ai/api/v1` | OpenAI-compatible endpoint |
| `LLM_API_KEY` | _unset_ | OpenRouter / Ollama / vLLM secret |
| `LLM_MODEL` | _unset_ | e.g. `meta-llama/llama-3.3-70b-instruct:free` |
| `LLM_TIMEOUT_SECONDS` | `60` | Per-request timeout |
| `GITHUB_TOKEN` | _unset_ | Optional, raises GitHub rate-limit |

> **DATABASE_URL search_path note** — the connection string ships with
> `?options=-csearch_path%3Dpublic` (URL-encoded `-c search_path=public`).
> This forces SQLx to store its `_sqlx_migrations` ledger in `public`
> rather than `ai_radar`. Without it, the ledger drifts to `ai_radar` once
> the schema is created and `sqlx migrate revert` cycles become
> unreliable. Migrations always qualify table names (`ai_radar.sources`,
> etc.) so the search path never affects domain queries.

## Migrations

```sh
just migrate         # sqlx migrate run --source migrations
just migrate-info    # see applied vs pending
just migrate-revert  # roll back the most recent migration
just migrate-add my-change  # create a new reversible pair
```

The `0001_init.down.sql` script intentionally **leaves the empty
`ai_radar` schema in place** after a revert — never drops it — so
SQLx-installed metadata in `public._sqlx_migrations` keeps working.

## Quality gates

| Gate | Command | Notes |
|---|---|---|
| Build | `just build` | `cargo build --workspace` |
| Tests | `just test` | `cargo test --workspace` |
| Lint | `just lint` | `cargo clippy --workspace --all-targets -- -D warnings` |
| Format | `just fmt-check` | `cargo fmt --check` |
| Kustomize dry-run | `just k8s-validate` | `kubectl apply --dry-run=client` sobre o overlay production |
| Harness | `just harness` | `tools/harness/verify.sh verify-changed` (whole repo) |

CI enforces the same set on every PR (see
[`AGENTS.md`](../../AGENTS.md) for the GitFlow workflow).

## Docker images

```sh
just docker-build-api   # ai-radar-api:dev (~26 MB, distroless nonroot)
just docker-build-cli   # ai-radar-cli:dev (~24 MB, distroless nonroot)
```

Both Dockerfiles are multi-stage and multi-arch (`linux/amd64` and
`linux/arm64`). The runtime layer is `gcr.io/distroless/cc-debian12:nonroot`
which gives us glibc (required by SQLx + reqwest with rustls + chrono) without
shipping a shell or package manager.

## Kubernetes (OCI / ARM64)

Follow [`deploy-service`](../../.agents/skills/deploy-service/SKILL.md): load the
tunnel + `oci-builder`, then deploy from **`apps/ai-radar`**:

```bash
cd apps/ai-radar

# Opcional antes do primeiro apply — valida manifests locais sem cluster:
just k8s-validate

# Build + push (ARM64 para Nexus) e apply do overlay production:
./deploy.sh
```

**Namespace e pull secret.** O overlay cria **`ai-radar`**. Secrets de registry são
por namespace; use o mesmo padrão `regsecret` que os outros serviços:

```bash
# A partir da raiz do repo, com kubectl apontando para o cluster-alvo:
./components/nexus/create_registry_secret.sh ai-radar
```

**`DATABASE_URL`.** [`k8s/base/secret-database-url.placeholder.yaml`](k8s/base/secret-database-url.placeholder.yaml)
contém apenas placeholders (`REPLACE_*`) para versionar formato e a query
`?options=-csearch_path%3Dpublic`. Em ambiente real, aplique uma variante gerada por
SealedSecrets, SOPS ou outro fluxo aprovado no cluster (**nunca** valores reais
no Git).

**Migrações na primeira subida.** A imagem da API é **distroless** (sem shell,
sem `wget`/`curl`). Não use `kubectl exec` para ferramentas de debug. Rode as
SQLx migrations a partir da sua estação (**ou** de um Job com imagem tooling),
com uma `DATABASE_URL` que alcance o mesmo Postgres aplicado pelo Secret do
deployment — por exemplo **`just migrate`** (ver [Migrations](#migrations)),
com rede/VPN até o host do banco já resolvido. Execute **antes** ou **entre**
restarts da API sempre que mudar revisão schema.

**Smoke no cluster.**

```bash
kubectl -n ai-radar get pods,svc deploy/ai-radar-api
kubectl -n ai-radar port-forward svc/ai-radar-api 18080:8080
curl -fsS http://127.0.0.1:18080/health
curl -fsS -H 'X-Request-Id: smoke-001' http://127.0.0.1:18080/sources
```

Se `kubeconform` estiver instalado, você pode usar o comando da task
[**T-174**](../../tasks/2026/Q2/T-174-AI-Radar-Kubernetes-Baseline-Primeiro-Deploy.md)
(`kubectl kustomize … | kubeconform …`) além do `just k8s-validate`.

## Troubleshooting

- **`error: rustc X is not supported`**: the workspace pins `1.88.0`. Run
  `rustup show` to confirm rustup picked it up; otherwise force install:
  `rustup install 1.88.0 --profile minimal --component rustfmt --component clippy`.
- **`Address already in use`**: another process is on `0.0.0.0:8080`. Set
  `AI_RADAR_API_BIND=127.0.0.1:18080` (or any free port).
- **Compose API restarts**: check `docker compose logs api`. Most often it is
  Postgres still warming up; the healthcheck loop should self-resolve in a few
  seconds.
- **`could not parse environment variable`**: a typed config field (e.g.
  `LLM_TIMEOUT_SECONDS`) received a value figment cannot coerce. The error
  message points to the offending variable.

## License

MIT. See repository root `LICENSE`.
