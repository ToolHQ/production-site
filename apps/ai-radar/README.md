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

**Em cluster (baseline):** workspace (**T-159**), Postgres/schema (**T-160**), RSS collect (**T-161**), LLM abstraction (**T-164**), extract/score pipelines (**T-165**/**T-166**), digest API/CLI (**T-169**), observability (**T-172**), manifests + CronJobs collect/extract/score (**T-171**/**T-174**). API em `ai-radar.dnor.io`; imagem em produção pode estar atrás do `main` — ver runbook **T-191**.

**Collectors:** RSS (**T-161**), GitHub releases/repo (**T-162**), webpage manual (**T-163**).

**Scorer LLM opcional (**T-167**):** `LLM_SCORING_ENABLED=true` + merge 70/30 com determinístico (PR #159).

**Entregue (MVP+):** console (**T-175**), dashboards (**T-176**), items explorer (**T-177**), feedback (**T-170**), hardening (**T-173**). Detalhes: [`tasks/KANBAN.md`](../../tasks/KANBAN.md).

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
├── deploy.sh                   # bash: namespace + regsecret + DATABASE_URL opcional + build + apply Kustomize
├── scripts/
│   └── render-ai-radar-database-url.py  # Opcional — monta DATABASE_URL com postgres-secret ( kubectl )
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
To hit a live model, set `LLM_ENABLED=true`, `LLM_API_KEY`, and `LLM_MODEL` in
`.env` (see [`T-164`](../../tasks/2026/Q2/T-164-AI-Radar-LLM-Provider-Abstraction.md)).
`LLM_BASE_URL` defaults to OpenRouter’s OpenAI-compatible API; override it for
**Ollama** (`http://localhost:11434/v1`), **vLLM**, or any compatible gateway.

**Free-tier OpenRouter models** (quotas and availability change with provider policy;
fine for dev, less predictable under load):

| Model | Notes |
| --- | --- |
| `meta-llama/llama-3.3-70b-instruct:free` | Strong general instruct; may queue when busy. |
| `google/gemini-2.0-flash-exp:free` | Fast “flash” tier; experimental naming/stability. |

## CLI

```sh
cargo run -p ai-radar-cli -- --help
cargo run -p ai-radar-cli -- collect --help
cargo run -p ai-radar-cli -- llm-ping --help
cargo run -p ai-radar-cli -- extract --help
cargo run -p ai-radar-cli -- score --help
```

**Score ([`T-166`](../../tasks/2026/Q2/T-166-AI-Radar-Scorer-Deterministico.md)).**
Deterministic ruleset `deterministic-v1` (no LLM): integer points start at **50**, rules add/subtract,
clamp to **[0, 100]**, map to `scores.score` as **points / 100**, thresholds **≥80 adopt**, **≥60 test**,
**≥35 monitor**, else **ignore**. Re-score after **24h** by default (`--stale-hours`), or pass
`--rescore-all` to bypass recency. Migration **`0003_scores_history`** drops the old unique constraint so
history keeps multiple rows per `(extracted_item_id, scoring_version)`.

```sh
export DATABASE_URL='postgres://…?options=-csearch_path%3Dpublic'
sqlx migrate run   # applies 0003 on existing DBs
cargo run -p ai-radar-cli -- score --limit 20
cargo run -p ai-radar-cli -- score --limit 50 --rescore-all
```

**Extract ([`T-165`](../../tasks/2026/Q2/T-165-AI-Radar-Extractor-Pipeline.md)).**
Requires `DATABASE_URL`, `LLM_ENABLED=true`, and valid `LLM_*` credentials.
Claims up to `--limit` pending `raw_items` (FIFO), runs the versioned LLM prompt
(`llm-v1`), inserts `extracted_items`, and sets `raw_items.status` to `extracted`
or `failed`. Concurrency is **1** per process (CronJob-safe).

```sh
export DATABASE_URL='postgres://…?options=-csearch_path%3Dpublic'
export LLM_ENABLED=true LLM_API_KEY='…' LLM_MODEL='…'
cargo run -p ai-radar-cli -- extract --limit 10
```

**Collect ([`T-161`](../../tasks/2026/Q2/T-161-AI-Radar-RSS-Collector.md)).**
Requires `DATABASE_URL`. Polls every **enabled** RSS source (or `--source-id`),
inserts idempotent `raw_items`, prints
`collected=… skipped=… errors=… (N sources, M skipped poll)` and exits **1** only
when **every polled source** fails. Batch runs **skip** sources still inside
`sources.poll_interval_minutes` since `last_polled_at` (use `--source-id` to
force one feed). RSS HTTP uses **retries** with jittered backoff on transient
5xx / 429 (`Retry-After` capped at 120s).

```sh
export DATABASE_URL='postgres://…?options=-csearch_path%3Dpublic'
cargo run -p ai-radar-cli -- collect
cargo run -p ai-radar-cli -- collect --source-type github_releases
cargo run -p ai-radar-cli -- collect --source-type github_repo
cargo run -p ai-radar-cli -- collect --source-type webpage
cargo run -p ai-radar-cli -- collect --source-id '<uuid>'
```

**GitHub ([`T-162`](../../tasks/2026/Q2/T-162-AI-Radar-GitHub-Collector.md)).**
`source_type` `github_releases` or `github_repo` with `url`
`https://github.com/{owner}/{repo}`. Releases use `release.id` as `external_id`.

**Webpage ([`T-163`](../../tasks/2026/Q2/T-163-AI-Radar-Webpage-Fetcher.md)).**
`source_type=webpage` — max **1 MiB** download, **50 KiB** cleaned text. **No JS
rendering** (static HTML only).

**`llm-ping` ([`T-164`](../../tasks/2026/Q2/T-164-AI-Radar-LLM-Provider-Abstraction.md)).**
Runs one completion via `build_llm_provider` (honours `LLM_*`, retries on 429/5xx).
Useful smoke test before wiring extract/score.

```sh
export LLM_ENABLED=true LLM_API_KEY='sk-or-…' LLM_MODEL='meta-llama/llama-3.3-70b-instruct:free'
cargo run -p ai-radar-cli -- llm-ping
cargo run -p ai-radar-cli -- llm-ping --prompt 'Say only: ok'
```

Further subcommands (`score`, `digest`, …) land in later epics. The CLI image
(`docker/Dockerfile.cli`) is the CronJob entrypoint.

**API:** `POST /extract/run` with JSON `{"limit": 50}` (defaults apply) triggers extract (needs `LLM_*`).
`POST /score/run` with `{"limit": 50, "stale_hours": 24, "rescore_all": false}` runs scoring (deterministic; optional LLM merge when `LLM_SCORING_ENABLED=true`).

Rule weights and predicates live in `crates/ai-radar-core/src/scorer/rules.rs` (roadmap-aligned; adjust there until config-driven scoring exists).

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
| `LLM_MAX_RPM` | `15` | Min spacing between LLM HTTP calls (`0` = off). Keeps OpenRouter `:free` under ~16–20 RPM |
| `GITHUB_TOKEN` | _unset_ | Optional — **60 req/h** without token, **5000 req/h** with token; client waits up to **90s** on `x-ratelimit-reset` |
| `LLM_SCORING_ENABLED` | `false` | LLM second opinion on score (requires `LLM_ENABLED=true`) |
| `LLM_SCORING_DETERMINISTIC_WEIGHT` | `0.7` | Weight for rule-based score when merging |
| `LLM_SCORING_LLM_WEIGHT` | `0.3` | Weight for LLM score when merging |
| `AI_RADAR_COLLECT_CONCURRENCY` | `2` | Parallel RSS fetches (`collect`) |
| `AI_RADAR_MAX_ITEMS_PER_RUN` | `50` | Cap entries ingested per source per run |
| _(código)_ | `util/limits.rs` | `MAX_RAW_CONTENT_BYTES` (200 KiB), futuros caps extract/LLM |

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

Follow [`deploy-service`](../../.agents/skills/deploy-service/SKILL.md): na raiz do repo carregue **`setup-dev-deploy.sh`** (socket buildkit remote + kubectl tunnel + auth Nexus), export **`KUBECONFIG`** tunnel, depois em **`apps/ai-radar`**:

```bash
cd ~/production-site
source oci-k8s-cluster/scripts/setup-dev-deploy.sh
export KUBECONFIG=/home/$(whoami)/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml

cd apps/ai-radar
just k8s-validate   # opcional

# Caminho automatizado recomendado para este cluster Postgres compartilhado:
AI_RADAR_FROM_CLUSTER_PG_SECRET=1 ./deploy.sh
```

**O que o `deploy.sh` faz só** (`bash`): `kubectl apply namespace`, **pipe automático**
`components/nexus/create_registry_secret.sh ai-radar → kubectl apply` (regsecret Nexus),
build/push **duas** imagens ARM64 — **`my-site-ai-radar-api`** (Deployment) e
**`my-site-ai-radar-cli`** (CronJob `ai-radar-collect` — ver
[`T-171`](../../tasks/2026/Q2/T-171-AI-Radar-Kubernetes-Operacao-Leve.md)) —, render
Kustomize + `kubectl apply` com tags **sincronizadas** (mesmo `TAG_VERSION`).

Após o apply, `kubectl -n ai-radar get cronjobs` deve listar **`ai-radar-collect`**
(`*/30 * * * *`), **`ai-radar-extract`** (`15,45 * * * *`), **`ai-radar-score`** (`5 * * * *`).
Smoke ad-hoc (exemplos):

`kubectl -n ai-radar create job --from=cronjob/ai-radar-collect collect-test-$(date +%s)`  
`kubectl -n ai-radar create job --from=cronjob/ai-radar-score score-test-$(date +%s)`

**Secret `ai-radar-llm` (CronJob extract).** Opcional no Git; quando ausente, o extract roda sem `LLM_*` e falha cedo (`LLM_ENABLED must be true`). Para habilitar:

`kubectl -n ai-radar create secret generic ai-radar-llm --from-literal=LLM_ENABLED=true --from-literal=LLM_API_KEY='…' --from-literal=LLM_MODEL='…'` (e opcionalmente `LLM_BASE_URL`, `LLM_TIMEOUT_SECONDS` — ver [`.env.example`](.env.example)).

 **`Secret ai-radar-database`** se ainda não existir (prioridade):

1. Reutiliza Secret já aplicado pelo operador (**SealedSecret / SOPS / manual** — preferido quando existir política forte).
2. Ou `AI_RADAR_DATABASE_URL='postgres://…' ./deploy.sh`.
3. Ou `AI_RADAR_FROM_CLUSTER_PG_SECRET=1` → monta URL com `postgres-secret`
   no namespace **`postgres`** (host default **`postgres-0.postgres-internal.postgres.svc.cluster.local`**
   — primário gravável; evita réplica hot-standby via `postgres-service` quando o Service ainda
   expõe ambos os pods).
   Overrides: `AI_RADAR_PG_HOST`, `AI_RADAR_PG_PORT` (ex. `36432` com `kubectl port-forward` local), `AI_RADAR_PG_DATABASE`.

**IMPORTANTE.** O recurso **`k8s/base/secret-database-url.placeholder.yaml`** continua apenas como template de referência; **não** entra mais no render Kustomize, para **`deploy.sh`/apply não pisarem uma `DATABASE_URL` real**.

**Docker build (T-200).** Imagens saem de **`docker/Dockerfile`** com **`cargo-chef`** + cache BuildKit compartilhado (`ai-radar-cargo-registry`, `ai-radar-cargo-target`). Baseline empírico no master: **~45–55 min** (API+CLI); com cache quente e só API, meta **&lt; 20 min**.

**Builder Hetzner (T-222, padrão desde PR #153).** O `deploy.sh` tenta **`hetzner-builder`** antes do **`oci-builder`** no master:

1. **Uma vez por máquina** (WSL): `~/production-site/oci-k8s-cluster/scripts/setup-hetzner-builder.sh` — exige SSH `hetzner-cax21-helsinki-4vcpu-8gb-ipv4` em `~/.ssh/config`.
2. **Cada deploy:** compilação ARM64 na VM Helsinki (`--load` na sua máquina); só abre túnel **`31444→master`** para `docker push` da imagem final (sem cache BuildKit no master).
3. **Emergência:** build no master só com `AI_RADAR_ALLOW_MASTER_BUILD=1` (pré-voo de disco ≥12 GiB). Por padrão o deploy **falha** se a Hetzner estiver indisponível — preserva o master.

```bash
# Verificar builder (deve mostrar Status: running, Platforms: linux/arm64)
docker buildx inspect hetzner-builder

AI_RADAR_FROM_CLUSTER_PG_SECRET=1 AI_RADAR_DEPLOY_CLI=0 ./deploy.sh
```

| Variável | Efeito |
| -------- | ------ |
| `AI_RADAR_DEPLOY_CLI=auto` (padrão) | Pula build CLI se o diff vs `origin/main` não tocar `crates/ai-radar-cli`, `crates/ai-radar-core`, `docker/` ou `Cargo.lock` |
| `AI_RADAR_DEPLOY_CLI=0` | Sempre pula CLI (reusa imagem do CronJob `ai-radar-extract`) |
| `AI_RADAR_DEPLOY_CLI=1` | Sempre builda API + CLI |
| `AI_RADAR_DIFF_BASE=origin/main` | Base do `git diff` para o modo `auto` |

Se aparecer **`context deadline exceeded`** no primeiro passo `#1 waiting for connection` no buildx **`oci-builder`**, o daemon **buildkitd** no **`oci-k8s-master`** ou o forwarding do socket ficou stale — volta a rodar **`setup-dev-deploy.sh`**; se persistir, use **`oci-k8s-cluster/k8s_ops_menu.sh`** para maintenance / comandos remotos até o worker remoto voltar a responder (ex. `buildctl debug workers`, ou revise `systemctl --user` do buildkit no master).

**Postgres só leitura / sem primário.** Writes devem ir ao **primário** (`postgres-0`). Se `DATABASE_URL` apontar para um Service que balanceia `postgres-1` (standby), jobs falham com `cannot execute UPDATE in a read-only transaction` e `raw_items` ficam presos em `extracting`. Use o host do primário (acima) ou `postgres-service` após o selector restringir só `postgres-0`. Se `pg_is_in_recovery()=true` no pod alvo, trate infra (**T-190**) antes de migrações (`deploy.sh` avisa).

**Migrações.** Rodar **`just migrate`** (ou Job tooling) quando houver endpoint **gravável** e com a mesma `DATABASE_URL` que o Deployment usa (ver [Migrations](#migrations)). Para aplicar do laptop contra o Postgres do cluster: túnel SSH + `KUBECONFIG` (ver `.agents/skills/connect-to-cluster`), `kubectl -n postgres port-forward svc/postgres-service 36432:5432`, depois `export DATABASE_URL="$(AI_RADAR_PG_HOST=127.0.0.1 AI_RADAR_PG_PORT=36432 python3 scripts/render-ai-radar-database-url.py)"` e `sqlx migrate run --source migrations` em `apps/ai-radar`.

**Smoke no cluster.** Checklist operacional completo (digest, métricas `ai_radar_*`, jobs manuais): [`T-191`](../../tasks/2026/Q2/T-191-AI-Radar-Cluster-Smoke-Demo-Runbook-post-T-169.md).

**Demo pipeline (console com conteúdo).** Script repetível que cadastra fontes RSS, dispara jobs collect/extract/score/digest e imprime o link do digest no console:

```bash
export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml
API_URL=https://ai-radar.dnor.io ./scripts/run-demo-pipeline.sh
```

Verifique em `https://ai-radar.dnor.io/#/digests` (seção **Testar**). O extract depende do LLM (`ai-radar-llm`); rate-limit do provedor free pode falhar lotes — o digest ainda usa scores já persistidos.

```bash
kubectl -n ai-radar get pods,svc deploy/ai-radar-api
kubectl -n ai-radar port-forward svc/ai-radar-api 18080:8080
curl -fsS http://127.0.0.1:18080/health
curl -fsS http://127.0.0.1:18080/metrics | head -30
curl -fsS http://127.0.0.1:18080/stats
curl -fsS -H 'X-Request-Id: smoke-001' http://127.0.0.1:18080/sources
# digest (requer imagem com T-169 aplicada no cluster)
curl -fsS -X POST http://127.0.0.1:18080/digest/run -H 'Content-Type: application/json' -d '{"period":"daily"}'
# reprocess (T-173) — nova versão extract e/ou score
curl -fsS -X POST http://127.0.0.1:18080/items/<extracted_item_id>/reprocess \
  -H 'Content-Type: application/json' -d '{"stage":"all"}'
```

**HTTPS público (Ingress).** Com o manifesto `k8s/base/ingress.yaml` aplicado, a API responde em **`https://ai-radar.dnor.io`** (TLS via cert-manager). **`GET /` serve o Operator Console** (**T-175**): painel, digests renderizados e fontes; `/health` e `/metrics` permanecem para probes e Prometheus. Garanta um registo **`A`** para `ai-radar.dnor.io` apontando para o **mesmo IP** do balanceador usado pelos outros hosts `*.dnor.io` (mesma família que `reports.dnor.io`). Smoke:

```bash
curl -fsS https://ai-radar.dnor.io/health
curl -fsS https://ai-radar.dnor.io/health/ready | jq .
curl -fsS https://ai-radar.dnor.io/stats
curl -fsS https://ai-radar.dnor.io/metrics | grep ai_radar | head
# fila extract: gauge atualizado a cada scrape
curl -fsS https://ai-radar.dnor.io/metrics | grep ai_radar_pending_raw_items
curl -fsS -H 'X-Request-Id: edge-001' https://ai-radar.dnor.io/sources
```

**Probes Kubernetes (T-264):** liveness → `GET /health` (sem DB). Readiness e startup → `GET /health/ready` (`SELECT 1`, budget 2s) — o pod só entra no Service quando Postgres responde.

**Dashboards ops (Prometheus / Grafana / Coroot).** Métricas `ai_radar_*` são scrapeadas pelo Prometheus do namespace `coroot` (anotações no Service). Importe o dashboard Grafana e queries em [`observability/README.md`](observability/README.md) (**T-176**). **SLOs e playbooks de incidente/rollout:** [`observability/RUNBOOK.md`](observability/RUNBOOK.md) (**T-266**).

Se `kubeconform` estiver instalado, você pode usar o comando da task
[**T-174**](../../tasks/2026/Q2/T-174-AI-Radar-Kubernetes-Baseline-Primeiro-Deploy.md)
(`kubectl kustomize … | kubeconform …`) além do `just k8s-validate`.

## Operator feedback (**T-170**)

Registrar feedback humano sobre um item scored e consultar divergências (quando o operador discorda da decisão automática):

```bash
export API=https://ai-radar.dnor.io
ITEM_ID=$(curl -fsS "$API/items?limit=1" -H 'Accept: application/json' \
  | jq -r '.items[0].extracted_item_id')

curl -fsS -X POST "$API/items/$ITEM_ID/feedback" \
  -H 'Content-Type: application/json' \
  -d '{"feedback_type":"rejected","notes":"não encaixa no cluster"}'

curl -fsS "$API/items/$ITEM_ID" -H 'Accept: application/json' | jq '.feedbacks'
curl -fsS "$API/reports/divergence?limit=20" -H 'Accept: application/json' | jq
curl -fsS "$API/items/$ITEM_ID/related?limit=5" -H 'Accept: application/json' | jq
curl -fsS "$API/search?q=agente%20coding&limit=10" -H 'Accept: application/json' | jq
# Duplicatas semânticas (relatório; default threshold 0.92, até 300 embeddings):
curl -fsS "$API/reports/semantic-duplicates?threshold=0.92&limit=20" -H 'Accept: application/json' | jq
```

Tipos válidos: `useful`, `irrelevant`, `duplicate`, `low_quality`, `wrong_category`, `adopted`, `tested`, `monitoring`, `rejected`.

Testes de integração (Postgres): `cargo test -p ai-radar-core --test feedback_integration -- --ignored`

## Embedding backfill (**T-256**)

O CronJob `ai-radar-embed` roda `ai-radar embed` sem `--limit`; o tamanho do lote vem de **`EMBED_BATCH_LIMIT`** (ConfigMap `ai-radar-config`, default **50**, teto **100** no binário).

**Catch-up (`ai-radar-embed-catchup`, T-260):** schedule `15 */4 * * *` (a cada 4 h, deslocado dos embeds regulares em `:25` e `:55`). O container injeta `EMBED_BATCH_LIMIT` a partir de **`EMBED_CATCHUP_BATCH_LIMIT`** (default **100**). Os dois CronJobs usam `concurrencyPolicy: Forbid` **cada um** — podem rodar em paralelo se os horários coincidirem; em geral o catch-up só acelera o esvaziamento da fila sem substituir o embed 2×/h.

Após cada pass do CronJob `ai-radar-extract`, o pipeline roda um embed tail automático (**T-259**): até **`POST_EXTRACT_EMBED_TAIL_LIMIT`** linhas (default **25**, mesmo teto **100**), desde que `EMBEDDINGS_ENABLED=true`.

Monitorar fila e cobertura:

```bash
export API=https://ai-radar.dnor.io
curl -fsS "$API/stats" | jq '.embeddings'
curl -fsS "$API/metrics" | grep -E 'ai_radar_embeddings_(pending|coverage_pct)'
```

**Alertas sugeridos (T-261):** ver [`observability/prometheus/alerting-rules.example.yaml`](observability/prometheus/alerting-rules.example.yaml) — disparam quando `ai_radar_embeddings_pending > 80` por **2h** ou `ai_radar_embeddings_coverage_pct < 50` por **4h**. Grafana: painéis no JSON [`observability/grafana/ai-radar-pipeline.json`](observability/grafana/ai-radar-pipeline.json).

**Quando disparar backfill:** após alerta ou se `coverage_pct` ficar abaixo da meta (~80%) com `embeddings_pending` > 0 — preferir job a partir de **`ai-radar-embed-catchup`** (lote 100); use `ai-radar-embed` para lotes menores e mais frequentes.

Backfill manual até `embeddings_pending` chegar a 0:

```bash
export KUBECONFIG=~/production-site-cursor/oci-k8s-cluster/kubeconfig_tunnel.yaml

while true; do
  pending=$(curl -fsS "$API/stats" | jq -r '.embeddings.embeddings_pending // 0')
  echo "embeddings_pending=$pending"
  [ "$pending" = "0" ] && break
  job="ai-radar-embed-backfill-$(date +%s)"
  kubectl create job "$job" --from=cronjob/ai-radar-embed-catchup -n ai-radar
  kubectl wait --for=condition=complete "job/$job" -n ai-radar --timeout=1200s
  kubectl logs -n ai-radar "job/$job" --tail=30 | grep -E 'embedded=|embed.coverage|pending_after'
done
```

Override pontual (ex. smoke de 10 itens): `ai-radar embed --limit 10`. Logs estruturados incluem `event=embed.coverage` com `pending_after` e `coverage_pct`.

## Failure modes (collect / RSS)

- **HTTP 5xx / 429 / timeouts**: o fetch do feed é **retentado** com backoff e jitter; ver logs do CronJob e Coroot para `source_id`.
- **Corpo maior que `MAX_RAW_CONTENT_BYTES` (200 KiB)**: a entrada é **descartada** (não truncada); métrica `ai_radar_entries_rejected_total{reason="oversize_body"}` incrementa; ver `crates/ai-radar-core/src/util/limits.rs`.
- **Batch dentro do `poll_interval`**: fonte não é consultada até passar o intervalo; use `--source-id` para forçar.
- **Só erros**: o CLI sai com código **1** apenas quando **todas** as fontes efetivamente polled falham.
- **Postgres indisponível**: conexão falha com `RepoError::Database` (sem panic); ver teste `postgres_unreachable_returns_database_error` em `tests/chaos.rs`.

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
