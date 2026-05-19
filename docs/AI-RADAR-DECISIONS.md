# AI Radar — Architecture & Decisions

> Documento de decisões técnicas e arquitetura do programa **AI Radar** (Decision Engine de curadoria contínua de ferramentas de IA).
>
> Este arquivo é a **spec consultada pelas tasks** `T-159..T-177` (épico AI Radar). Os passos de execução vivem em cada task individual (`tasks/2026/Q2/T-XXX-AI-Radar-*.md`). Aqui ficam só decisões transversais, schema, contratos e riscos.

## Origem

- **Prompt-pai**: `docs/AI-RADAR-ROADMAP.md` (super prompt do usuário descrevendo a visão completa).
- **Status**: MVP backend em cluster; **Fase 16 (visual)** planejada — T-175 console thin slice, T-176 dashboards ops, T-177 explorer de itens (ver `docs/AI-RADAR-ROADMAP.md` §Fase 16).
- **Owner**: AI Radar / DevExp.

## Visão de produto

Sistema self-hosted que **monitora → coleta → deduplica → estrutura → pontua → compara → recomenda** novidades de IA, entregando digest acionável com decisão `adopt | test | monitor | ignore`. Não é mais um agregador — é um **Decision Engine**.

## Decisões fundamentais

| Decisão | Escolha | Motivo |
|---|---|---|
| Linguagem | **Rust** | Footprint baixo (cluster ARM64 1 vCPU/6GB), tipagem forte, async maduro |
| Framework HTTP | **Axum 0.7 + Tokio** | Idiomático, leve, ecossistema |
| ORM/DB layer | **SQLx 0.8 com `rustls`** | Sem `openssl-sys` — crítico pro build distroless ARM64 |
| Banco | **Postgres compartilhado do cluster, schema dedicado `ai_radar`** | Reaproveita instância existente, isolamento por schema |
| Local do código | **`apps/ai-radar/`** (workspace Cargo, 3 crates: `core`/`api`/`cli`) | Convive com `apps/rs-axum-back-end` |
| LLM provider | **Trait `LlmProvider` + impl OpenRouter** (OpenAI-compatible) | OpenRouter free tier; trait deixa porta aberta pra Ollama/vLLM/local |
| LLM como dependência | **Opcional**: `LLM_ENABLED=false` mantém pipeline 100% determinístico | Resiliência + Zero Variable Cost |
| **NÃO usar LiteLLM** | Recente supply-chain attack | Decisão explícita do usuário |
| Imagens Docker | **Distroless `gcr.io/distroless/cc-debian12:nonroot`** multi-arch | <80MB, nonroot, glibc presente |
| Jobs | **Kubernetes CronJobs** (não workers 24/7) | Cluster pequeno; ciclos curtos previsíveis |
| Logs | **JSON estruturado** com `request_id`/`job_id` | Cluster usa Coroot/Loki potencialmente |
| Exposição HTTP (cluster) | **Ingress nginx + TLS** em **`https://ai-radar.dnor.io`** (`cert-manager` / `dnor-ca-issuer`, secret `ai-radar-ingress-tls`) | Mesmo padrão de `reports.dnor.io` / `coroot.dnor.io`; DNS `A` para o load balancer OCI |
| Métricas | **Prometheus** via `/metrics` | Padrão do cluster |
| OpenTelemetry/Langfuse | Hooks prontos, **desligados por feature flag** | Liga só quando coletor estiver disponível |
| **Superfície visual MVP** | **Console estático** servido pelo `ai-radar-api` (`include_dir`) + dashboards Coroot/Grafana | Mesmo padrão **T-133** (`reports.dnor.io`); sem segundo pod; digest Markdown como “relatório principal” até `GET /items` |

## Superfície visual (Fase 16 — decisões)

| Decisão | Escolha | Motivo |
| --- | --- | --- |
| Onde vive a UI | **`ai-radar-api`** em `/`, `/digests`, `/sources` | Zero custo extra de réplica; CORS simples (same-origin) |
| Stack front V1 | HTML + CSS + JS vanilla (`fetch` → JSON/Markdown) | Sem toolchain Node no deploy ARM64; alinhado a cluster pobre |
| Render de digest | Client-side Markdown → HTML **sanitizado** (coordenar com T-173) | `GET /digests/:id` já suporta `Accept: text/markdown` |
| Dashboards SRE | **Coroot/Grafana** sobre `/metrics` | Não misturar métricas de infra com UX de produto |
| Autenticação V1 | **Nenhuma** (read-only público como hoje) | Ingress já é TLS interno; write (POST sources) fica para V2 ou Basic Auth no Ingress |
| Explorer de itens | **T-177** após `GET /items` + **T-170** feedback | Roadmap API ainda parcial vs implementação |

**Referência de implementação no monorepo:** `apps/rs-observability-api` (static + API no mesmo binário, ingress dedicado).

## Estrutura de código alvo

```
apps/ai-radar/
├── Cargo.toml                 # workspace
├── rust-toolchain.toml        # 1.83.0
├── crates/
│   ├── ai-radar-core/         # domínio, repos, providers, pipelines (lib)
│   ├── ai-radar-api/          # bin: Axum HTTP server
│   └── ai-radar-cli/          # bin: clap CLI (collect/extract/score/digest/...)
├── migrations/                # SQLx migrations no schema ai_radar
├── docker/
│   ├── Dockerfile.api
│   └── Dockerfile.cli
├── docker-compose.yaml        # postgres + api dev
├── k8s/
│   ├── base/                  # Kustomize base
│   └── overlays/production/   # overlay produção (cluster OCI)
├── observability/             # (T-176) dashboards Grafana/Coroot export JSON
├── crates/ai-radar-api/
│   └── assets/                # (T-175) HTML/CSS/JS estáticos embutidos
├── .env.example
└── README.md
```

## Modelo de dados (schema `ai_radar`)

| Tabela | Função | Chaves/constraints críticas |
|---|---|---|
| `sources` | Fontes monitoradas | `source_type` CHECK in (`rss`, `github_repo`, `github_releases`, `webpage`, `youtube`); `last_polled_at`, `last_error` |

Inventário prod, taxonomia `tier`/`topic` e matriz keep/add/remove: [`AI-RADAR-SOURCES.md`](AI-RADAR-SOURCES.md) (**T-267**).
| `raw_items` | Conteúdo cru coletado | `(source_id, content_hash) UNIQUE` (idempotência); `external_id` p/ GitHub release.id |
| `extracted_items` | Saída do Extractor (1:1 inicial, depois versionado) | `version int NOT NULL DEFAULT 1` para reprocess |
| `scores` | Pontuação determinística + LLM merged | `scoring_version` para auditoria; `metadata_json` jsonb com contribuições |
| `feedback` | Feedback humano | `feedback_type` enum 9 valores |
| `digests` | Markdown gerado (daily/weekly) | `digest_type` enum |
| `comparisons` | Matriz por categoria | adicionada na Fase 10 |

**FKs**: cascata onde apropriado; preservação de histórico onde for útil para auditoria.

## API (Axum)

```
GET    /health
GET    /metrics                        # Prometheus
GET    /sources           POST /sources           PATCH /sources/:id
POST   /collect/run       POST /extract/run       POST /score/run    POST /digest/run
GET    /items?limit&offset&decision&category&sort   GET  /items/:id  # latest + score history (**T-177**)
POST   /items/:id/feedback
POST   /items/:id/reprocess { stage }
GET    /digests           GET  /digests/:id       # text/markdown via Accept
POST   /compare           # { category, top_n }
GET    /reports/divergence
```

## CLI (clap)

```
ai-radar collect [--source-id <uuid>] [--source-type rss]
ai-radar extract [--limit N]
ai-radar score   [--limit N] [--rescore-all]
ai-radar compare --category <str> [--top N]
ai-radar digest  --daily | --weekly
ai-radar reprocess --item <id> --stage <extract|score|all>
ai-radar run-all
```

## Resource budget alvo (cluster OCI ARM64)

| Workload | requests cpu | requests mem | limits cpu | limits mem |
|---|---:|---:|---:|---:|
| API (Deployment) | 25m | 64Mi | 250m | 256Mi |
| CronJob (collect/extract/score/digest) | 50m | 128Mi | 500m | 512Mi |

`activeDeadlineSeconds: 600` (10 min cap por job). `concurrencyPolicy: Forbid`.

## Schedules iniciais (CronJobs)

| Job | Cron | Janela alvo |
|---|---|---|
| `collect` | `*/30 * * * *` | A cada 30 min |
| `extract` | `15,45 * * * *` | 15 e 45 de cada hora |
| `score` | `5 * * * *` | A cada hora aos 5min |
| `digest-daily` | `0 6 * * *` | 06:00 UTC diário |
| `digest-weekly` | `0 7 * * 1` | Segunda 07:00 UTC |

Ajustáveis via overlay sem tocar base.

## Variáveis de ambiente

```
AI_RADAR_API_BIND=0.0.0.0:8080
AI_RADAR_LOG_LEVEL=info
DATABASE_URL=postgres://USER:PASS@HOST:5432/ai_radar
LLM_ENABLED=true|false
LLM_BASE_URL=https://openrouter.ai/api/v1
LLM_API_KEY=...
LLM_MODEL=meta-llama/llama-3.3-70b-instruct:free
LLM_TIMEOUT_SECONDS=60
LLM_SCORING_ENABLED=false
GITHUB_TOKEN=ghp_...                    # opcional
AI_RADAR_COLLECT_CONCURRENCY=2
MAX_RAW_CONTENT_BYTES=200000
MAX_EXTRACT_INPUT_TOKENS=8000
MAX_CONCURRENT_LLM_REQUESTS=2
```

## Mapa de épicos (T-159..T-174)

| ID | Fase | Épico | Estim. | Depende de |
|---|---|---|---|---|
| T-159 | 1 | Bootstrap Rust Workspace | 1d | — |
| T-160 | 2 | Banco e Modelo de Dados | 1d | T-159 |
| T-174 | 2b | Kubernetes — baseline primeiro deploy API | 4h | T-160 |
| T-161 | 3 | RSS Collector | 1d | T-160 |
| T-162 | 4 | GitHub Collector | 1d | T-160 (paralelo a T-161) |
| T-163 | 5 | Webpage Fetcher | 4h | T-160 (paralelo) |
| T-164 | 6 | LLM Provider Abstraction | 4h | T-159 |
| T-165 | 7 | Extractor Pipeline | 1d | T-164 + T-161 (≥1 collector) |
| T-166 | 8 | Scorer Determinístico | 1d | T-165 |
| T-167 | 9 | Scorer com LLM Opcional | 4h | T-166 + T-164 |
| T-168 | 10 | Comparator | 4h | T-166 |
| T-169 | 11 | Digest Generator | 1d | T-166 |
| T-170 | 12 | Feedback Loop | 4h | T-169 |
| T-171 | 13 | Kubernetes — CronJobs e demo agendado | 1d | T-174 + T-169 (+ produtos T-161/T-165/T-166 conforme cada job) |
| T-172 | 14 | Observabilidade | 4h | T-174 (mínimo); completar smoke CronJob após **T-171** |
| T-173 | 15 | Hardening | 1d | T-172 |

### Caminho crítico até MVP demo-ready (produto)

`T-159 → T-160 → T-161 → T-164 → T-165 → T-166 → T-169 → T-171`

### Validação incremental no cluster (recomendado)

Subir **`T-174` logo após `T-160`** (paralelo a **T-161** / **T-164**) para falhar cedo em imagem Nexus, probes, limits e `DATABASE_URL` no Postgres compartilhado. **`T-171`** adiciona CronJobs e fecha o MVP **agendado** no cluster; não concentrar apenas no fim o risco de infra.

### Diagrama rápido (ondas K8s)

```text
T-160 ──► T-174  (Deployment API + Service + Secret + smoke /health,/sources)
            │
            └──────────────► (paralelo pipeline produto até T-169)
                                           │
                                           ▼
                                    T-171 CronJobs (+ opcional gancho TUI)
```

## Riscos transversais

| Risco | Prob. | Impacto | Mitigação |
|---|---|---|---|
| OpenRouter free models instáveis | Alta | Médio | Trait `LlmProvider` permite trocar; modo deterministic-only sempre disponível |
| Postgres compartilhado sob pressão | Média | Alto | Schema isolado + pool max=8; prepared statements; observar Coroot |
| Build ARM64 lento no CI | Média | Baixo | `cargo-chef` cache; matrix paralelo |
| RSS feeds quebrarem parser | Alta | Baixo | Erro isolado por fonte; fixtures de regressão |
| Coleta gera muitos tokens LLM = custo | Média | Médio | Truncate, MAX_*, `LLM_SCORING_ENABLED=false` default |
| Cluster ARM64 sem libs nativas | Baixa | Médio | Distroless `cc-debian12` (glibc); SQLx com `rustls` |
| Schema `ai_radar` colide com app existente | Baixa | Alto | Auditar schemas antes de T-160; nome dedicado garante namespace |

## Convenções de execução (vinculadas ao `AGENTS.md`)

- **GitFlow obrigatório**: branch `feat/T-XXX-<slug>` a partir de `main` atualizada.
- **Nunca commit direto em `main`**: tudo via PR com review.
- **Skill `manage-tasks`** para mover entre Backlog → In Progress → Done (`tools/manage_tasks.sh`).
- **Skill `deploy-service`** para builds/push Nexus + apply manifests.
- **Stability First**: nada que ameace serviços críticos (Postgres, Nexus, Longhorn, ingress).

## Definition of Done global (MVP)

- [ ] `apps/ai-radar` builda em ARM64 e amd64 (CI matrix).
- [ ] `docker compose up` sobe ambiente local funcional.
- [ ] `sqlx migrate run` aplica schema `ai_radar` em Postgres compartilhado.
- [ ] `ai-radar collect` coleta de RSS + GitHub.
- [ ] `ai-radar extract` produz extracted_items via OpenRouter.
- [ ] `ai-radar score` aplica regras determinísticas + (opcional) LLM.
- [ ] `ai-radar digest --weekly` gera Markdown legível.
- [ ] API `/health`, `/sources`, `/items`, `/digests`, `/feedback` funcionam.
- [ ] CronJobs no cluster respeitam `activeDeadlineSeconds` e resource budget.
- [ ] Logs JSON com `job_id` rastreáveis no kubectl logs.
- [ ] `/metrics` Prometheus expõe contadores do pipeline.
- [ ] Sistema tolera falha de fonte/LLM/Postgres sem corromper estado.
- [ ] PR por épico, todos merged via review (GitFlow).

## Referências

- `docs/AI-RADAR-ROADMAP.md` — super prompt original.
- `AGENTS.md` — protocolos do agente, GitFlow, briefing.
- `.agents/skills/manage-tasks/SKILL.md` — gestão de KANBAN.
- `.agents/skills/deploy-service/SKILL.md` — pattern Build & Apply.
- `.agents/skills/operational-safety/SKILL.md` — proteções pré-ação destrutiva.
