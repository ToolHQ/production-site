# PROJETO: agent-meter

Criar um projeto open-source, inicialmente para uso pessoal/laboratório na Norio Company, fora do ambiente do banco, chamado `agent-meter`.

O objetivo do projeto é medir e analisar consumo, desperdício de contexto e eficiência de fluxos de desenvolvimento com agentes de IA, especialmente usando ferramentas como:

- VS Code + GitHub Copilot
- Cursor
- Google Antigravity
- Claude Code
- OpenCode
- MCP servers próprios ou de terceiros

A ideia **NÃO** é criar um clone completo do Langfuse. O foco inicial é ser um coletor leve, seguro, extensível e barato para rodar em infraestrutura pequena, como OCI Free Tier (ARM64) ou uma VPS barata.

---

# OBJETIVO PRINCIPAL

Criar uma ferramenta que responda perguntas como:

- Quais MCP tools mais geram consumo de tokens?
- Quais tools retornam payloads grandes demais?
- Quais skills/prompts/instructions causam mais tool calls?
- Quais tasks de desenvolvimento custam mais?
- Quais MCPs falham mais ou geram mais retries?
- Qual IDE/agente gera mais chamadas para resolver o mesmo tipo de problema?
- Quais schemas MCP são grandes demais e merecem otimização?
- Quais skills/MCPs devem ser refatorados para reduzir custo, latência e contexto?

---

# RESTRIÇÕES IMPORTANTES

- O projeto deve ser leve.
- Preferência por Rust.
- Storage inicial em PostgreSQL.
- Deve expor eventos também via OpenTelemetry.
- Não deve salvar prompt completo nem resposta completa por padrão.
- Deve salvar hashes, tamanhos, metadados e estimativas.
- Deve permitir modo seguro/local-first.
- Deve ser fácil de rodar via Docker Compose.
- Deve ser preparado para futuramente virar open-source.
- Não usar dependências SaaS obrigatórias.
- Não depender de Langfuse, Phoenix, Opik ou serviços externos.
- Não implementar autenticação complexa no MVP, mas deixar estrutura preparada.
- Evitar overengineering.
- **ARM64**: O cluster OCI usa nós Ampere ARM64. Imagens Docker devem suportar `linux/arm64`.

---

# STACK DESEJADA

## Backend/collector

- Rust (edition 2021)
- Axum
- Tokio
- SQLx (com PostgreSQL)
- OpenTelemetry SDK
- tracing + tracing-subscriber
- serde + serde_json
- uuid
- chrono
- anyhow/thiserror
- clap para CLI
- tower-http (para CORS nas fases iniciais)

## Infra local

- Docker Compose
- PostgreSQL
- opcionalmente Jaeger ou OTEL Collector depois

## Formato de observabilidade

- JSON logs estruturados
- PostgreSQL como storage analítico principal
- OpenTelemetry spans para integração futura com Jaeger/Grafana/Datadog/etc.

---

# ARQUITETURA INICIAL DESEJADA

```txt
agent tools / MCP wrappers / CLIs / IDE integrations
        |
        v
agent-meter collector HTTP API
        |
        +--> PostgreSQL
        |
        +--> OpenTelemetry spans
        |
        +--> JSON structured logs
```

---

# COMPONENTES DO PROJETO

O projeto vive dentro de `apps/agent-meter/` neste monorepo. A estrutura inicial é:

```txt
apps/agent-meter/
├── Cargo.toml              # workspace root (se multi-crate) ou crate único
├── README.md
├── docker-compose.yml      # dev local auto-contido (Postgres + collector)
├── .env.example
├── .env                    # gitignored, copiado de .env.example
├── .gitignore
├── .dockerignore
├── Dockerfile              # build ARM64 para deploy no cluster
├── deploy.sh               # padrão: buildx --platform linux/arm64 + kubectl apply
├── k8s/
│   └── agent-meter.yaml    # manifesto Kubernetes
├── crates/
│   ├── collector/
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── main.rs
│   │       ├── app.rs
│   │       ├── config.rs
│   │       ├── db.rs
│   │       ├── errors.rs
│   │       ├── telemetry.rs
│   │       ├── routes/
│   │       │   ├── mod.rs
│   │       │   ├── health.rs
│   │       │   ├── events.rs
│   │       │   └── reports.rs
│   │       ├── models/
│   │       │   ├── mod.rs
│   │       │   ├── event.rs
│   │       │   ├── task.rs
│   │       │   └── tool_call.rs
│   │       └── services/
│   │           ├── mod.rs
│   │           ├── token_estimator.rs
│   │           ├── event_service.rs
│   │           └── report_service.rs
│   ├── cli/
│   │   ├── Cargo.toml
│   │   └── src/
│   │       └── main.rs
│   └── mcp-wrapper/
│       ├── Cargo.toml
│       └── src/
│           └── main.rs
├── migrations/
│   ├── 20260517000001_init.sql
│   └── 20260517000002_indexes.sql
└── docs/                   # docs específicos do agent-meter (não conflita com o /docs raiz)
    ├── architecture.md
    ├── event-schema.md
    ├── security.md
    ├── mcp-wrapper-design.md
    └── roadmap.md
```

---

# MVP ESPERADO

Implementar primeiro apenas o necessário para validar a ideia.

---

## FASE 1 - COLLECTOR HTTP

Criar um serviço HTTP em Rust com Axum contendo:

- `GET /health`
- `POST /events/tool-call`
- `GET /reports/top-tools`
- `GET /reports/top-tasks`
- `GET /reports/top-mcp-servers`

O collector deve:

- Ler config via env vars.
- Conectar no PostgreSQL.
- Criar logs JSON estruturados.
- Receber eventos de tool call.
- Calcular tokens estimados quando não vierem informados.
- Persistir no PostgreSQL.
- Gerar um span OpenTelemetry para cada tool call recebida.
- Retornar erros JSON padronizados.

---

## FASE 2 - SCHEMA POSTGRESQL

Criar migrations SQL para estas tabelas:

```sql
create table agent_tasks (
  id bigserial primary key,
  task_id text not null unique,
  repo text,
  branch text,
  ide text,
  agent text,
  skill text,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
);

create table agent_tool_calls (
  id bigserial primary key,
  event_id uuid not null unique,
  task_id text,
  repo text,
  branch text,
  ide text,
  agent text,
  skill text,
  mcp_server text,
  tool_name text not null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  duration_ms integer not null,
  ok boolean not null,
  error text,
  request_bytes integer,
  response_bytes integer,
  estimated_input_tokens integer,
  estimated_output_tokens integer,
  estimated_total_tokens integer,
  request_sha256 text,
  response_sha256 text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table agent_mcp_schemas (
  id bigserial primary key,
  schema_id uuid not null unique,
  mcp_server text not null,
  tool_name text,
  schema_sha256 text not null,
  schema_bytes integer not null,
  estimated_schema_tokens integer not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
```

Criar indexes:

```sql
create index idx_agent_tool_calls_task_id on agent_tool_calls(task_id);
create index idx_agent_tool_calls_started_at on agent_tool_calls(started_at);
create index idx_agent_tool_calls_tool on agent_tool_calls(mcp_server, tool_name);
create index idx_agent_tool_calls_ide on agent_tool_calls(ide);
create index idx_agent_tool_calls_skill on agent_tool_calls(skill);
create index idx_agent_tool_calls_metadata_gin on agent_tool_calls using gin(metadata);
```

---

## FASE 3 - EVENTO UNIVERSAL

O endpoint `POST /events/tool-call` deve aceitar este JSON:

```json
{
  "event_id": "4b6fdf08-ef7f-4f0e-9df5-7859c30505fb",
  "task_id": "TASK-001",
  "repo": "agent-meter",
  "branch": "main",
  "ide": "cursor",
  "agent": "cursor-agent",
  "skill": "rust-mcp-observability",
  "mcp_server": "filesystem",
  "tool_name": "read_file",
  "started_at": "2026-05-17T12:00:00Z",
  "ended_at": "2026-05-17T12:00:01Z",
  "ok": true,
  "error": null,
  "request_bytes": 1200,
  "response_bytes": 30000,
  "estimated_input_tokens": null,
  "estimated_output_tokens": null,
  "request_sha256": "abc123",
  "response_sha256": "def456",
  "metadata": {
    "model": "unknown",
    "provider": "unknown",
    "workspace": "/workspace/agent-meter",
    "source": "manual-test"
  }
}
```

Regras:

- Se `event_id` não vier, gerar UUID.
- Se `duration_ms` não vier, calcular com `ended_at - started_at`.
- Se `estimated_input_tokens` não vier, estimar usando `request_bytes / 4`.
- Se `estimated_output_tokens` não vier, estimar usando `response_bytes / 4`.
- `estimated_total_tokens = input + output`.
- Não salvar prompt completo.
- Não salvar resposta completa.
- Apenas hashes, bytes e metadados seguros.

---

## FASE 4 - OPENTELEMETRY

Para cada tool call recebida, criar span com nome:

```txt
agent.tool_call
```

Atributos do span:

```txt
agent.task_id
agent.repo
agent.branch
agent.ide
agent.name
agent.skill
mcp.server
mcp.tool_name
tool.duration_ms
tool.ok
tool.request_bytes
tool.response_bytes
gen_ai.usage.input_tokens
gen_ai.usage.output_tokens
gen_ai.usage.total_tokens
```

Não quebrar o collector se OTEL endpoint não estiver configurado.

Variáveis de ambiente:

```env
AGENT_METER_HOST=0.0.0.0
AGENT_METER_PORT=8081          # 8080 já usado pelo nginx local
DATABASE_URL=postgres://agent_meter:agent_meter@localhost:5432/agent_meter
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
OTEL_SERVICE_NAME=agent-meter
RUST_LOG=info
```

---

## FASE 5 - REPORTS INICIAIS

Criar endpoints simples:

### `GET /reports/top-tools`

Retornar ranking por `mcp_server`, `tool_name`:

- calls
- total estimated tokens
- avg duration
- errors
- avg response bytes

### `GET /reports/top-tasks`

Retornar ranking por `task_id`:

- tool calls
- total estimated tokens
- total duration
- errors
- distinct tools

### `GET /reports/top-mcp-servers`

Retornar ranking por `mcp_server`:

- calls
- total estimated tokens
- avg response bytes
- error rate

Aceitar query params opcionais:

```txt
from
to
repo
ide
skill
limit
```

---

## FASE 6 - CLI INICIAL

Criar CLI `agent-meter` com comandos:

```bash
agent-meter task start TASK-001 --repo agent-meter --ide cursor --skill rust-mcp-observability
agent-meter task end TASK-001
agent-meter event tool-call --task-id TASK-001 --mcp-server filesystem --tool-name read_file --request-bytes 1200 --response-bytes 30000 --ok true
agent-meter report top-tools
```

No MVP, a CLI pode chamar o collector HTTP.

Variável:

```env
AGENT_METER_COLLECTOR_URL=http://localhost:8081
```

---

## FASE 7 - MCP WRAPPER INICIAL

Criar o crate `mcp-wrapper`, mas nesta primeira etapa pode ser apenas um esqueleto documentado.

Objetivo futuro:

```txt
IDE/agent -> agent-meter mcp-wrapper -> MCP real
```

O wrapper deve futuramente medir:

- tools/list
- tools/call
- schema bytes
- schema token estimate
- request bytes
- response bytes
- duration
- error
- retry
- task_id
- repo
- ide
- skill

Mas **NÃO** implementar tudo agora se isso atrasar o collector.

---

# SEGURANÇA

Desde o início, implementar estes princípios:

- Não salvar prompt completo por padrão.
- Não salvar resposta completa por padrão.
- Não salvar env vars completas.
- Não salvar secrets.
- Usar hashes SHA-256 de request/response quando necessário.
- Metadata deve ser JSONB, mas documentar que não deve conter segredos.
- Preparar configuração futura para redaction/blocklist.
- Documentar riscos em `docs/security.md`.

---

# DOCKER COMPOSE

Criar `apps/agent-meter/docker-compose.yml` com:

- PostgreSQL
- collector
- opcionalmente Jaeger comentado ou em profile separado

Este compose é auto-contido para dev local. Futuramente pode ser integrado ao `apps/docker-compose.yaml` existente.

Exemplo desejado:

```bash
docker compose up -d postgres
cargo sqlx migrate run
cargo run -p collector
```

Ou:

```bash
docker compose up --build
```

**⚠️ Porta**: usar `8081` (host) mapeando para `3000` (container) para evitar conflito com o nginx local que já usa `8080`.

---

# README INICIAL

O `apps/agent-meter/README.md` deve conter:

- O que é o projeto.
- Problema que resolve.
- O que ele não é.
- Como rodar local (docker compose + sqlx).
- Como enviar um evento manual com curl.
- Como consultar reports.
- Como configurar OTEL.
- Como fazer deploy no cluster OCI (ARM64).
- Roadmap.
- Aviso de segurança.

Exemplo de pitch:

```txt
agent-meter is a lightweight, open-source observability and FinOps collector for agentic development workflows.

It tracks MCP tool calls, estimated token usage, payload size, latency, errors and task-level cost across tools like Cursor, VS Code Copilot, Antigravity, Claude Code, OpenCode and custom agents.
```

---

# CRITÉRIOS DE ACEITE DO MVP

O projeto deve estar aceitável quando:

1. `docker compose up` sobe PostgreSQL e collector.
2. `GET /health` retorna OK.
3. `POST /events/tool-call` grava evento no banco.
4. Tokens estimados são calculados automaticamente.
5. Eventos aparecem nos reports.
6. Logs são JSON estruturados.
7. O collector gera spans OTEL quando endpoint está configurado.
8. Sem OTEL configurado, o collector continua funcionando.
9. README permite rodar o projeto do zero.
10. Não há gravação de prompt/resposta completa por padrão.

---

# ESTILO DE CÓDIGO

- Código simples e legível.
- Evitar abstrações desnecessárias.
- Criar módulos pequenos.
- Usar erros tipados.
- Usar structs claras para request/response.
- Usar SQL explícito com SQLx.
- Não usar ORM pesado.
- Criar testes básicos para token estimator, parsing de eventos e reports.
- Manter comentários úteis, sem excesso.
- Priorizar entrega funcional incremental.

---

# IMPORTANTE

Não tente implementar tudo de uma vez.

Primeiro entregue:

1. Estrutura do workspace Rust.
2. Collector com `/health`.
3. Docker Compose com Postgres.
4. Migration inicial.
5. `POST /events/tool-call`.
6. Primeiro report `/reports/top-tools`.
7. README mínimo.

Depois evoluímos para CLI, OTEL completo, MCP wrapper e dashboards.

Trabalhe em pequenos commits lógicos.

---

# APÓS GERAR A PRIMEIRA VERSÃO

Depois de gerar a base inicial, revise o projeto com foco em simplicidade, segurança e execução local.

Procure especificamente por:

1. Lugares onde prompt, resposta, headers, env vars ou secrets possam ser gravados indevidamente.
2. Acoplamento excessivo.
3. Erros ruins de configuração.
4. Queries SQL sem índices adequados.
5. Ausência de timeout.
6. Ausência de graceful shutdown.
7. Falhas no comportamento quando OTEL não está configurado.
8. Inconsistências entre README, `.env.example` e `docker-compose`.
9. Compatibilidade ARM64 (Dockerfile, `deploy.sh`).
10. Problemas para rodar em uma VPS pequena/OCI Free Tier.

Depois aplique correções mínimas, sem mudar a arquitetura.

---

# GERAR TASKS NO KANBAN

Com base no estado atual do projeto, criar cards no formato do `tasks/OPENCODE-QUEUE.md` (se o agente OpenCode for o executor) ou em `tasks/KANBAN.md` seguindo o padrão T-ID.

Use este formato:

```txt
| T-ID | Título | Status | Prioridade | Owner |
|------|--------|--------|------------|-------|
| T-XXX | título curto | 🔜 Backlog | 🔼 High | OpenCode |
```

Cada task deve ter um card detalhado no formato:

```txt
### T-XXX — título curto

**Objetivo:** ...
**Escopo:** ...
**Fora de escopo:** ...
**Arquivos esperados:** ...
**Critérios de aceite:** ...
**Comandos de validação:** ...
```

As tasks devem ser pequenas o suficiente para um agente resolver uma por vez.

Priorize primeiro collector, Postgres, segurança e reports.

Deixe MCP wrapper, dashboards e integrações com IDEs para fases posteriores.
