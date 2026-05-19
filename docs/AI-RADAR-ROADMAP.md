# Roadmap de Tasks — AI Radar / Curadoria Contínua de Ferramentas de IA

Você é um agente de engenharia responsável por transformar esta visão em um plano executável de desenvolvimento, quebrado em tasks pequenas, incrementais e com Definition of Done.

## Contexto

Estamos criando um sistema self-hosted de curadoria contínua de conteúdos, ferramentas, vídeos, repositórios e papers sobre IA.

O objetivo é reduzir overload informacional. O sistema deve pesquisar, coletar, resumir, estruturar, rankear, comparar e priorizar novidades de IA automaticamente, entregando um digest acionável.

O foco não é criar mais um agregador de conteúdo, mas um Decision Engine.

A saída final esperada não é apenas resumo, mas recomendações como:

- ADOTAR
- TESTAR
- MONITORAR
- IGNORAR

## Restrições técnicas importantes

- Priorizar aplicações em Rust.
- O cluster alvo roda em OCI Free Tier / ambiente limitado.
- Evitar componentes pesados.
- Evitar JVM.
- Evitar stack com consumo alto de memória.
- Preferir binários pequenos, baixa memória e baixa CPU.
- Preferir jobs assíncronos e agendados em vez de workers 24/7 quando possível.
- Preferir arquitetura modular, simples e observável.
- Tudo deve poder rodar em Kubernetes pobre.
- Evitar dependência obrigatória de SaaS externo.
- O sistema deve ser desenhado para uso self-hosted/in-house.
- A arquitetura deve permitir trocar o provedor de LLM.
- O sistema deve permitir uso com LLM local, OpenAI-compatible endpoint, LiteLLM interno ou outro gateway compatível.

## Objetivo do sistema

Construir um radar automatizado de IA que:

1. Monitora fontes confiáveis.
2. Coleta conteúdos novos.
3. Deduplica itens repetidos.
4. Extrai metadados estruturados.
5. Resume conteúdos.
6. Classifica por categoria.
7. Calcula score baseado no nosso contexto.
8. Compara ferramentas da mesma categoria.
9. Gera recomendações acionáveis.
10. Entrega digest diário/semanal.
11. Mantém histórico de decisões.
12. Aprende com feedback manual.

## Escopo inicial do MVP

O MVP deve focar em:

- RSS/Atom feeds
- GitHub repositories/releases
- Páginas web simples
- YouTube transcripts, se for simples e viável
- Digest em Markdown
- Persistência em PostgreSQL
- API HTTP simples em Rust
- Jobs agendados
- Scoring inicial determinístico + LLM opcional
- **UI mínima no MVP** (Fase 16): console estático leve servido pela própria API — não SPA pesada no início

## Stack preferencial

Use Rust sempre que fizer sentido.

Sugestões:

- Rust
- Axum para API HTTP
- Tokio para async runtime
- SQLx para PostgreSQL
- Reqwest para HTTP client
- Serde para JSON
- Tracing para logs
- Cron-like scheduler leve ou Kubernetes CronJobs
- PostgreSQL como banco principal
- pgvector opcional, apenas se realmente necessário
- Docker multi-stage build
- Imagem final distroless ou debian slim
- Kubernetes manifests simples
- OpenTelemetry opcional, mas preparar tracing/logs estruturados

Evitar inicialmente:

- Airflow
- Spark
- Elasticsearch
- Kafka
- JVM services
- UI complexa
- Multi-agent framework pesado
- Dependência obrigatória de LangChain
- Dependência obrigatória de SaaS externo

## Arquitetura desejada

Organizar o sistema em módulos ou serviços pequenos.

### Componentes sugeridos

#### 1. Collector

Responsável por coletar novos itens de fontes configuradas.

Fontes iniciais:

- RSS/Atom
- GitHub repos monitorados
- GitHub releases
- URLs manuais
- Lista de canais ou fontes confiáveis

Responsabilidades:

- Buscar novos itens
- Normalizar dados brutos
- Evitar coleta duplicada
- Persistir item bruto
- Registrar fonte, timestamp, URL e hash de conteúdo

#### 2. Extractor

Responsável por extrair informações estruturadas.

Campos esperados:

{
"title": "...",
"url": "...",
"source_type": "rss | github | youtube | webpage | paper",
"tool_name": "...",
"category": "...",
"problem_solved": "...",
"target_users": ["developers", "platform", "data", "security"],
"stack_fit": ["rust", "python", "typescript", "kubernetes"],
"self_hosted": true,
"saas_only": false,
"license": "...",
"maturity": "experimental | early | growing | stable",
"risk_level": "low | medium | high",
"summary": "...",
"key_points": ["...", "..."],
"recommended_action": "adopt | test | monitor | ignore"
}

#### 3. Scorer

Responsável por calcular uma pontuação personalizada.

Score inicial sugerido:

+5 resolve dor atual
+4 self-hosted
+4 roda bem em Kubernetes
+3 tem adoção real
+3 reduz custo
+3 melhora produtividade de desenvolvimento
+2 suporta Rust/Python/TypeScript
+2 tem documentação boa
+2 tem licença clara
+2 tem releases recentes

-5 SaaS-only sem opção self-hosted
-5 exige envio de dados sensíveis para fora
-4 parece apenas wrapper superficial
-4 projeto sem manutenção
-3 documentação ruim
-3 licença confusa
-3 alto consumo de recursos
-2 hype sem evidência técnica

A saída do scorer deve ser:

{
"score": 0,
"decision": "adopt | test | monitor | ignore",
"reasons": ["...", "..."],
"risks": ["...", "..."],
"next_step": "..."
}

#### 4. Comparator

Responsável por comparar ferramentas da mesma categoria.

Exemplos de categorias:

- LLM observability
- AI coding agents
- MCP servers
- Prompt engineering tools
- Evaluation frameworks
- Vector databases
- RAG frameworks
- Browser automation
- Code review/security tools

Comparar apenas itens da mesma categoria.

Critérios de comparação:

- Self-hosted
- Consumo de recursos
- Licença
- Maturidade
- Comunidade
- Integração com Kubernetes
- Facilidade de deploy
- Fit com stack interna
- Risco de vendor lock-in
- Qualidade de documentação
- Última atividade/release

#### 5. Digest Generator

Responsável por gerar um relatório em Markdown.

Formato esperado:

# AI Radar Digest — YYYY-MM-DD

## 🔥 Testar esta semana

### 1. Nome da ferramenta

- Score: 87
- Categoria: LLM observability
- Motivo: ...
- Riscos: ...
- Próximo passo: ...

## 👀 Monitorar

### 2. Nome da ferramenta

- Score: 61
- Categoria: ...
- Motivo: ...

## ❌ Ignorar

### 3. Nome da ferramenta

- Score: 18
- Motivo: ...

#### 6. Feedback Loop

Permitir registrar feedback manual:

- useful
- not_useful
- wrong_category
- wrong_score
- already_known
- tested_good
- tested_bad
- adopted
- rejected

Esse feedback deve ser usado futuramente para ajustar scoring.

## Requisitos não funcionais

- Baixo consumo de memória.
- Logs estruturados em JSON.
- Configuração por environment variables.
- Sem segredos hardcoded.
- Retry com backoff em chamadas externas.
- Timeout em todas as chamadas HTTP.
- Rate limit básico.
- Idempotência nos collectors.
- Tolerância a falhas por fonte.
- Não derrubar o job inteiro se uma fonte falhar.
- Persistir erros de coleta/processamento.
- Permitir reprocessar item manualmente.
- Permitir rodar local via Docker Compose.
- Permitir deploy em Kubernetes.
- Healthcheck HTTP.
- Readiness check.
- Métricas simples, se possível.

## Modelo de dados inicial

Propor migrations SQL para PostgreSQL.

Entidades mínimas:

### sources

Representa fontes monitoradas.

Campos sugeridos:

- id
- name
- source_type
- url
- enabled
- poll_interval_minutes
- created_at
- updated_at

### raw_items

Conteúdos coletados ainda crus.

Campos sugeridos:

- id
- source_id
- external_id
- url
- title
- raw_content
- content_hash
- published_at
- collected_at
- status

### extracted_items

Conteúdo já estruturado.

Campos sugeridos:

- id
- raw_item_id
- tool_name
- category
- summary
- problem_solved
- self_hosted
- saas_only
- license
- maturity
- risk_level
- stack_fit
- metadata_json
- created_at

### scores

Pontuação e decisão.

Campos sugeridos:

- id
- extracted_item_id
- score
- decision
- reasons_json
- risks_json
- next_step
- scoring_version
- created_at

### feedback

Feedback manual.

Campos sugeridos:

- id
- extracted_item_id
- feedback_type
- notes
- created_at

### digests

Relatórios gerados.

Campos sugeridos:

- id
- digest_type
- markdown_content
- generated_at

## APIs desejadas

Criar uma API HTTP simples com Axum.

Endpoints mínimos:

GET /health
GET /sources
POST /sources
PATCH /sources/:id
POST /collect/run
POST /extract/run
POST /score/run
POST /digest/run
GET /items
GET /items/:id
POST /items/:id/feedback
GET /digests
GET /digests/:id

## CLI desejada

Além da API, criar um CLI simples para uso via CronJob.

Comandos desejados:

ai-radar collect
ai-radar extract
ai-radar score
ai-radar digest
ai-radar run-all

O CLI e a API podem compartilhar os mesmos módulos internos.

## Estratégia de execução

Gerar tasks em fases.

Cada fase deve ter:

- Objetivo
- Tasks pequenas
- Arquivos prováveis
- Critérios de aceite
- Testes esperados
- Riscos
- Ordem recomendada

## Fase 1 — Bootstrap do projeto Rust

Gerar tasks para:

- Criar workspace Rust.
- Definir crates/módulos.
- Configurar Axum.
- Configurar tracing JSON.
- Configurar dotenv/env vars.
- Criar healthcheck.
- Criar Dockerfile multi-stage.
- Criar docker-compose com PostgreSQL.
- Criar migrations iniciais.
- Criar README inicial.

Definition of Done:

- cargo test passa.
- API sobe local.
- /health responde.
- Docker build funciona.
- Docker compose sobe API + PostgreSQL.
- Logs saem em JSON.

## Fase 2 — Banco e modelo de dados

Gerar tasks para:

- Criar migrations.
- Configurar SQLx.
- Criar repositories.
- Criar models com Serde.
- Criar camada de configuração.
- Criar testes de integração com Postgres.

Definition of Done:

- Migrations executam.
- CRUD básico de sources funciona.
- Testes cobrem inserts/selects principais.

## Fase 3 — RSS Collector

Gerar tasks para:

- Implementar collector RSS/Atom.
- Buscar feeds com timeout.
- Parsear itens.
- Gerar hash de conteúdo.
- Evitar duplicidade.
- Persistir em raw_items.
- Registrar erro por fonte sem quebrar tudo.

Definition of Done:

- Adiciono uma source RSS.
- Rodo ai-radar collect.
- Itens novos aparecem em raw_items.
- Rodar duas vezes não duplica.
- Erros são logados.

## Fase 4 — GitHub Collector

Gerar tasks para:

- Monitorar releases de repos configurados.
- Monitorar README/metadados básicos de repo.
- Buscar stars, forks, open issues, pushed_at, license.
- Persistir como raw_items ou metadata.
- Respeitar token opcional GITHUB_TOKEN.
- Implementar rate limit básico.

Definition of Done:

- Consigo monitorar um repo.
- Releases novas são coletadas.
- Metadados relevantes são persistidos.
- Funciona sem token com limite menor.
- Funciona com token via env var.

## Fase 5 — Webpage Fetcher simples

Gerar tasks para:

- Buscar uma URL manual.
- Extrair título.
- Extrair texto simples do HTML.
- Remover scripts/styles.
- Limitar tamanho máximo de conteúdo.
- Persistir em raw_items.

Definition of Done:

- URL manual vira raw_item.
- Conteúdo é limpo o suficiente para resumo.
- Não explode memória com página grande.

## Fase 6 — LLM Provider Abstraction

Gerar tasks para:

- Criar trait/interface para provedor LLM.
- Implementar provider OpenAI-compatible.
- Configurar endpoint por env var.
- Configurar model por env var.
- Configurar timeout.
- Configurar max tokens.
- Criar mock provider para testes.
- Garantir que o sistema rode sem LLM em modo deterministic-only.

Variáveis sugeridas:

LLM_ENABLED=true
LLM_BASE_URL=http://localhost:4000/v1
LLM_API_KEY=...
LLM_MODEL=...
LLM_TIMEOUT_SECONDS=60

Definition of Done:

- Provider real funciona com endpoint OpenAI-compatible.
- Mock provider funciona em testes.
- Sistema não depende rigidamente de um SaaS.

## Fase 7 — Extractor

Gerar tasks para:

- Criar prompt de extração estruturada.
- Enviar raw_content para LLM.
- Validar JSON retornado.
- Aplicar fallback se JSON vier inválido.
- Persistir extracted_items.
- Criar versão do extractor/prompt.
- Limitar tamanho do input.
- Criar testes com mock LLM.

Prompt base do extractor:

Você é um avaliador técnico de ferramentas de IA.
Extraia informações estruturadas do conteúdo abaixo.
Responda somente JSON válido, sem Markdown.

Campos obrigatórios:
title, tool_name, category, problem_solved, target_users, stack_fit,
self_hosted, saas_only, license, maturity, risk_level, summary, key_points.

Se não souber um campo, use null.
Não invente informações.

Definition of Done:

- Raw item vira extracted item.
- JSON inválido não quebra processamento.
- Campos principais são persistidos.
- Testes usam mock LLM.

## Fase 8 — Scorer determinístico

Gerar tasks para:

- Implementar scoring sem LLM.
- Criar regras versionadas.
- Persistir score.
- Classificar decisão final.
- Gerar reasons e risks.
- Permitir configurar pesos por arquivo/env no futuro.

Decision thresholds iniciais:

score >= 80: adopt
score >= 60: test
score >= 35: monitor
score < 35: ignore

Definition of Done:

- Extracted item recebe score.
- Score é reprodutível.
- Reasons explicam por que ganhou/perdeu pontos.
- Testes cobrem casos principais.

## Fase 9 — Scorer com LLM opcional

Gerar tasks para:

- Criar avaliador LLM opcional.
- Comparar score determinístico com julgamento LLM.
- Persistir ambos ou mesclar com pesos.
- Evitar hallucination pedindo justificativas baseadas apenas no conteúdo.
- Criar modo LLM_SCORING_ENABLED.

Definition of Done:

- Sistema funciona com e sem LLM scoring.
- LLM não é obrigatório.
- Score final tem explicabilidade.

## Fase 10 — Comparator

Gerar tasks para:

- Agrupar ferramentas por categoria.
- Comparar apenas itens semelhantes.
- Gerar matriz simples de comparação.
- Gerar resumo comparativo em Markdown.
- Persistir resultado.

Definition of Done:

- Comparação não mistura categorias incompatíveis.
- Comparação gera output legível.
- Pode ser chamada sob demanda.

## Fase 11 — Digest Generator

Gerar tasks para:

- Selecionar itens recentes.
- Agrupar por decisão.
- Gerar Markdown.
- Persistir digest.
- Expor via API.
- Gerar por CLI.
- Permitir digest diário e semanal.

Definition of Done:

- ai-radar digest gera relatório.
- Relatório contém testar/monitorar/ignorar.
- Digest fica salvo no banco.
- API lista digests.

## Fase 12 — Feedback Loop

Gerar tasks para:

- Endpoint de feedback.
- Persistência de feedback.
- Exibir feedback no item.
- Preparar ajuste futuro de score baseado em feedback.
- Criar relatório de divergência entre decisão do sistema e decisão humana.

Definition of Done:

- Usuário consegue registrar feedback.
- Feedback aparece no item.
- Histórico de feedback é preservado.

## Fase 13 — Kubernetes e operação leve

Gerar tasks para:

- Criar manifests Kubernetes.
- Deployment da API.
- CronJob para coleta.
- CronJob para extração.
- CronJob para scoring.
- CronJob para digest.
- ConfigMap.
- Secret.
- Resource requests/limits baixos.
- Readiness/liveness probes.

Sugestão de limites iniciais:

resources:
requests:
cpu: "25m"
memory: "64Mi"
limits:
cpu: "250m"
memory: "256Mi"

Definition of Done:

- Roda em cluster pequeno.
- Jobs não ficam 24/7 sem necessidade.
- Cada etapa pode ser executada separadamente.
- Falha de um job não derruba os demais.

## Fase 14 — Observabilidade

Gerar tasks para:

- Logs JSON com request_id/job_id.
- Métricas simples.
- Contadores de itens coletados, processados e com erro.
- Tempo por etapa.
- Custo aproximado de LLM se disponível.
- Preparar integração futura com Langfuse ou OpenTelemetry.

Definition of Done:

- Logs permitem debugar uma execução.
- Cada job informa quantos itens processou.
- Erros têm contexto suficiente.

## Fase 15 — Hardening

Gerar tasks para:

- Retries com backoff.
- Timeouts globais.
- Limite de tamanho de conteúdo.
- Rate limit por fonte.
- Sanitização de HTML.
- Controle de concorrência.
- Idempotência.
- Reprocessamento manual.
- Testes de falha.

Definition of Done:

- Sistema não explode com fonte quebrada.
- Sistema não duplica dados.
- Sistema não consome memória sem limite.
- Sistema tolera falhas parciais.

## Fase 16 — Superfície visual do MVP (Operator Console)

> **Por quê agora:** o pipeline backend (coleta → extract → score → digest) já roda no cluster; sem uma camada visual o produto parece “invisível” (só JSON em `/health`). Esta fase fecha o MVP para **operador e stakeholder** sem abandonar as restrições do cluster (ARM64, 256Mi, zero SaaS).

### Princípios de desenho

| Princípio | Escolha |
| --------- | ------- |
| Fonte de verdade | **APIs e Postgres existentes** — a UI só consome HTTP; não duplica regras de score/digest |
| Runtime | **Mesmo binário `ai-radar-api`** serve assets estáticos em `/` (padrão validado em `rs-observability-api` / **T-133**) |
| Stack front | **HTML + CSS + JS vanilla** (ou **htmx** se precisar de poucos POSTs sem SPA) — sem React/Vite no V1 |
| Assets | **`include_dir` / `rust_embed`** no crate `api` — sem sidecar nginx, sem segundo Deployment |
| Ops vs produto | **Duas camadas:** dashboards Prometheus/Coroot (SRE) + console `ai-radar.dnor.io` (digest e fila) |
| Custo | **+0 pods**, footprint alvo **&lt; 128 KiB** de assets gzip + mesmos limits do Deployment |

### Camada A — Dashboards de operação (sem código novo no `ai-radar`)

Reutiliza **`GET /metrics`** (já exposto) e o stack de observabilidade do cluster:

- **Coroot / Prometheus:** painel com `ai_radar_pending_raw_items`, `ai_radar_scored_total`, `ai_radar_stage_duration_seconds`, falhas de job (via logs estruturados `job_id`).
- **Grafana (opcional):** JSON de dashboard versionado em `apps/ai-radar/observability/grafana/` (import manual ou ConfigMap).
- **Alertas mínimos:** fila `pending` alta por N horas; `score_failed_total` subindo.

**Task sugerida:** `T-176` — AI Radar — Dashboard pack (Coroot/Grafana) _(~2h, Owner Infra/Observability ou Cursor)_.

**DoD:** operador vê saúde do pipeline sem `curl`; link documentado no README.

### Camada B — Console produto “thin slice” (MVP visual)

Substituir o redirect `GET /` → `/health` por uma **home operacional** em `https://ai-radar.dnor.io/`.

#### Páginas V1 (somente leitura + 1 ação segura)

| Rota UI | Consome API | Valor para quem abre o browser |
| ------- | ----------- | ------------------------------ |
| `/` | `GET /stats`, link para último digest | Cards: fontes ativas, `raw_items`, pendentes de extract |
| `/digests` | `GET /digests` | Lista de digests (daily/weekly) com data |
| `/digests/:id` | `GET /digests/:id` + `Accept: text/markdown` | **Relatório renderizado** (Adotar / Testar / Monitorar / Ignorar) |
| `/sources` | `GET /sources` | Tabela de fontes RSS/GitHub (enabled, poll interval) |
| _(opcional V1.1)_ | `POST /digest/run` via botão + confirmação | Gerar digest sob demanda sem `curl` |

**Não entra no V1:** CRUD completo de sources, lista de itens scored, feedback — depende de `GET /items` (**T-177**) e **T-170**.

#### Contratos API a completar antes do explorer rico

O roadmap original previa endpoints ainda não implementados; para UI de itens:

- `GET /items` — lista paginada (`extracted_item` + último score + decisão)
- `GET /items/:id` — detalhe + histórico de versões + scores
- `POST /items/:id/feedback` — **T-170**

Até lá, o **digest Markdown** é o principal artefato “human-readable” do MVP.

#### Task sugerida: `T-175` — AI Radar — Operator Console (thin slice)

**Estimativa:** 4–6h | **Owner:** Cursor / AI Radar | **Depende de:** T-169, T-172, T-174 (baseline Ingress).

**Escopo:**

- [ ] Módulo `routes/ui.rs` + assets em `crates/ai-radar-api/assets/` (ou `static/`)
- [ ] `GET /` serve `index.html`; `GET /assets/*` para CSS/JS
- [ ] Viewer Markdown client-side (ex.: **marked** via CDN interno ou asset vendored — preferir **vendored** para air-gap)
- [ ] Páginas `/digests`, `/digests/:id`, `/sources` como HTML estático com `fetch()` à mesma origem
- [ ] Manter `GET /health` e `/metrics` **sem** autenticação (igual hoje); documentar que console é **read-only** no V1
- [ ] Smoke: abrir `https://ai-radar.dnor.io/` no browser e ver último digest renderizado
- [ ] README + runbook **T-191** atualizados com screenshots ou passos de demo

**DoD:**

- Stakeholder não técnico entende o estado do radar em **&lt; 30 s** na home.
- Último digest legível sem `curl` nem editor Markdown externo.
- `cargo test` + gate `rust-ai-radar` verdes; imagem ARM64 dentro do budget atual.

**Riscos mitigados:**

- XSS em Markdown → sanitizar HTML gerado (alinhar com **T-173** sanitize) ou renderizar subset seguro.
- Memória → não cachear digests grandes no servidor; streaming/paginação na lista.

### Camada C — Explorer de itens (pós–thin slice)

**Task sugerida:** `T-177` — AI Radar — Items API + UI explorer _(1d)_.

- API `GET /items`, `GET /items/:id` conforme modelo §APIs desejadas.
- UI: tabela filtrável por `decision`, `category`, score; drill-down com versões e botão **reprocess** (já existe API).
- Integração futura: feedback (**T-170**), comparator (**T-168**).

### Ordem recomendada no programa

```
Fase 15 (T-173 hardening) ──► Fase 16B (T-175 console) ──► Fase 16A (T-176 dashboards)
                                      │
                                      └──► encher pipeline (fontes + CronJobs + LLM)
                                      └──► Fase 16C (T-177 explorer) após GET /items
```

> **Nota:** a regra “não criar UI antes do pipeline” aplica-se às Fases 1–14. A partir da Fase 16 o pipeline já é demonstrável; a UI é **consumidor**, não substituto do backend.

## Fase 17 — Curadoria, sinais e ranking (concluída)

| ID | Entrega |
| --- | --- |
| T-232 | Extract quality gate |
| T-231 | Entity resolution / dedup cross-fonte |
| T-233 | Adoption signals (GitHub → score) |
| T-234 | Popularity velocity & snapshots |
| T-235 | Explorer ranking & badges |
| T-238 | Source health / noise scoring |
| T-237 | Comparator no console |
| T-236 | Feedback-calibrated scoring v2 |

## Fase 18 — Inteligência operacional no console (concluída)

**Tema:** expor no digest e no Operator Console os sinais já calculados na Fase 17.

| ID | Entrega | Est. |
| --- | --- | --- |
| T-241 | Digest v2 — seções trending, adoção, alertas de fonte | 6h |
| T-242 | Explorer — painel de sinais no detalhe do item | 4h |
| T-243 | Console — relatórios duplicatas & divergência | 4h |
| T-244 | Explorer — filtros `velocity_tier` / health / quality | 4h |
| T-245 | Compare deep-link por categoria | 2h |
| T-246 | Digest `metadata_json` + stats strip (`GET /stats`) | 4h |

## Fase 19 — Semântica leve (embeddings & busca) (concluída)

**Tema:** embeddings via gateway OpenRouter-compatible já provisionado; cosine em Rust; busca e related items no console; dedup semântico só como relatório (não auto-skip).

| ID | Entrega | Est. |
| --- | --- | --- |
| T-247 | Embedding provider + schema Postgres | 6h |
| T-248 | Pipeline/CronJob embed pós-extract | 4h |
| T-249 | `GET /search` semântico | 4h |
| T-250 | Explorer — barra de busca semântica | 4h |
| T-251 | Related items no detalhe do item | 4h |
| T-252 | Relatório clusters duplicatas semânticos | 6h |

PRs: #231, #235, #236, #237. Deploy API tag `1779065738`.

**Pós-deploy operacional:** migrações `0005`–`0007` aplicadas; secret `ai-radar-llm` com `EMBEDDINGS_ENABLED=true` + `EMBEDDING_MODEL=openai/text-embedding-3-small`. Batch embed exige **CLI** com subcomando `embed` (rebuild/push quando Nexus/registry estiver saudável).

Fila Cursor: [`tasks/CURSOR-QUEUE.md`](../tasks/CURSOR-QUEUE.md) § Fase 19.

**Fora de escopo:** pgvector managed, SPA React dedicada, auto-merge de duplicatas semânticas.

## Fase 20 — Semântica em produção (concluída)

**Tema:** tornar embeddings operacionais em escala — cobertura visível, backfill previsível, UX que explica estados vazios; drill-down no relatório de duplicatas.

| ID | Entrega | Est. |
| --- | --- | --- |
| T-255 | Cobertura de embeddings em `GET /stats` + gauge Prometheus + card no console | 3h |
| T-256 | Batch embed configurável + runbook de backfill no cluster | 4h |
| T-257 | Related items e empty-states semânticos no Explorer | 3h |
| T-258 | Console — drill-down em duplicatas semânticas | 4h |

PRs: #245, #248, #251, #253. Deploy API `1779103228`.

**Dependências:** Fase 19 + **T-254** (CLI `embed` no cluster). **Fora de escopo:** pgvector, auto-merge de duplicatas, novo collector YouTube.

Fila Cursor: [`tasks/CURSOR-QUEUE.md`](../tasks/CURSOR-QUEUE.md) § Fase 20 — **concluída**.

## Fase 21 — Cobertura semântica alvo 80% (em andamento)

**Tema:** fechar a fila de embeddings (~50% cobertura hoje) — tail pós-extract maior, catch-up agendado, alertas e visibilidade no Explorer.

| ID | Entrega | Est. |
| --- | --- | --- |
| T-259 | Post-extract embed tail configurável (`POST_EXTRACT_EMBED_TAIL_LIMIT`) | 3h |
| T-260 | CronJob `ai-radar-embed-catchup` (backfill agressivo) | 3h |
| T-261 | Alerta Prometheus cobertura / fila embed | 2h |
| T-262 | Explorer badge “sem vetor” + filtro | 3h |

**Meta operacional:** `embeddings_pending → 0` ou `coverage_pct ≥ 80` — **atingida (~91%)**.

Fila Cursor: [`tasks/CURSOR-QUEUE.md`](../tasks/CURSOR-QUEUE.md) § Fase 21 — **concluída**.

## Fase 22 — Resiliência & estabilidade do backend

**Tema:** eliminar rajadas de ERROR no Coroot, probes corretos, degradação graciosa — **sem** mudar pipeline de negócio.

| ID | Entrega | Est. | Ordem |
| --- | --- | --- | --- |
| T-263 | Metrics scrape cache + stale-while-revalidate | 3h | 1 |
| T-264 | Readiness probe com check Postgres | 2h | 2 |
| T-265 | Graceful degradation `/stats` e rotas read-only | 4h | 3 |
| T-266 | Pipeline SLO runbook | 2h | 4 |

**Princípio:** uma task por PR; deploy API após T-263/T-264.

## Fase 23 — Inteligência de fontes & trends

**Tema:** feeds curados (vendors IA), watchlist coding tools, modelos/preços, Google/YouTube trends — **planejamento antes de código**.

| ID | Entrega | Est. | Ordem |
| --- | --- | --- | --- |
| T-267 | Audit RSS + taxonomia (keep/add/remove) | 3h | 1 |
| T-268 | Curated AI vendor RSS pack | 4h | 2 |
| T-269 | Watchlist: Cursor, Copilot, Antigravity, Claude Code, OpenCode, OpenRouter | 6h | 3 |
| T-270 | Monitor modelos LLM & preços (OpenRouter diff) | 6h | 4 |
| T-271 | Spike Google Trends collector | 4h | 5 |
| T-272 | YouTube AI trends collector | 6h | 6 |
| T-273 | Collect relevance gate (pré-extract) | 5h | 7 |
| T-274 | Console Sources curation UX | 4h | 8 |
| T-275 | Digest “AI Tools Pulse” | 4h | 9 |

**Fora de escopo imediato:** pgvector, auto-merge duplicatas, re-scoring massivo.

Fila Cursor: [`tasks/CURSOR-QUEUE.md`](../tasks/CURSOR-QUEUE.md) § Fases 22–23.

## Entregável esperado deste prompt

Gere um roadmap de implementação com tasks pequenas e executáveis.

Para cada task, inclua:

## Task N — Título

### Objetivo

### Escopo

### Arquivos prováveis

### Passos

### Definition of Done

### Testes

### Observações

## Regras para geração das tasks

- Não gerar tasks gigantes.
- Cada task deve ser implementável isoladamente.
- Priorizar MVP funcional antes de sofisticação.
- Não introduzir dependências pesadas sem justificar.
- Não criar UI **antes** do pipeline funcionar (Fases 1–14); Fase 16 assume pipeline smoke OK (**T-191**).
- Não usar multi-agent framework no MVP.
- Não assumir SaaS obrigatório.
- Gerar primeiro a fundação Rust.
- Depois banco.
- Depois collectors.
- Depois extraction/scoring.
- Depois digest.
- Depois Kubernetes.
- Depois observabilidade e hardening.
- Depois superfície visual MVP (Fase 16: console + dashboards).

## Preferência de estrutura de código

Sugerir algo próximo de:

ai-radar/
Cargo.toml
crates/
ai-radar-core/
ai-radar-api/
ai-radar-cli/
migrations/
docker/
k8s/
README.md

Ou estrutura equivalente, desde que simples.

## Critério final de sucesso

Ao final do MVP, deve ser possível:

1. Subir Postgres + API local.
2. Cadastrar fontes RSS/GitHub.
3. Rodar coleta.
4. Extrair informações estruturadas.
5. Calcular score.
6. Gerar digest Markdown.
7. Consultar itens e digests pela API.
8. Rodar os jobs por CLI ou Kubernetes CronJob.
9. Operar em cluster pequeno com baixo consumo.
10. Abrir **`https://ai-radar.dnor.io/`** e ver estado do pipeline + último digest renderizado (Fase 16 / **T-175**).
11. Evoluir depois para explorer de itens (**T-177**), comparator (**T-168**), embeddings e dashboards Coroot (**T-176**).

## Instrução final

Comece apenas gerando o roadmap e as tasks. Não implemente código ainda.

Depois de eu aprovar a ordem das tasks, implemente uma task por vez, sempre preservando:

- simplicidade
- baixo consumo
- testabilidade
- arquitetura Rust idiomática
- operação em cluster Kubernetes pequeno
- dependências leves
- capacidade de rodar localmente via Docker Compose
