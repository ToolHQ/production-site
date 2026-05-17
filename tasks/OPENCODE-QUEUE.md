# OpenCode Queue

> Fila exclusiva do OpenCode.
> O `tasks/KANBAN.md` continua sendo a fonte de verdade para T-IDs.

## Regras de Uso

- OpenCode opera em `~/production-site-opencode`.
- OpenCode trabalha em tasks com `Owner` contendo `OpenCode`.
- OpenCode não altera `apps/ai-radar/` enquanto Cursor estiver owner.
- OpenCode não altera `apps/rs-observability-api/web-v2/` enquanto Antigravity estiver owner.
- Micro-tasks ficam só neste arquivo; T-IDs ficam no KANBAN.

## Em Andamento

| ID / Ref | Tarefa | Tipo |
| :------- | :----- | :--- |

## Próximas

| ID / Ref | Tarefa | Prioridade |
| :------- | :----- | :--------- |

## Micro-Tasks

- [x] Isolar `~/production-site-opencode` em worktree própria partindo de `origin/main`.
- [x] Criar estrutura inicial `apps/agent-meter/` conforme spec (`docs/agent-meter-spec.md`).
- [x] Workspace Cargo (collector, cli, mcp-wrapper).
- [x] Collector MVP: config, db, telemetry, routes, models, services.
- [x] Docker Compose, Dockerfile ARM64, deploy.sh, migrations, README.
- [x] Dashboard UI embarcada (HTML dark-theme com reports + form de teste).
- [x] Testar build local (`cargo check` 0 erros, release build OK).
- [x] Teste end-to-end local: Docker PostgreSQL → migrations → POST /events → GET /reports → GET /dashboard.
- [x] Deploy OCI: criar DB `agent_meter` no cluster PostgreSQL, criar secret, build/push imagem, aplicar manifest.
- [x] Validar deploy no cluster: health, evento, reports confirmados via nginx pod.
- [x] Otimização: migrar deploy.sh para Hetzner remote builder (build 4min vs 10min no master)
- [x] Atualizar Dockerfile para Rust 1.88 (despina home crate)
- [x] Rebase no main com melhorias do builder Hetzner
- [x] Fase 2: CLI `agent-meter` com comandos `task start/end/list`, `event tool-call`, `report top-tools/tasks/servers`.
- [x] Fase 2b: Task management routes no collector (POST /tasks/start, POST /tasks/end, GET /tasks).
- [x] Fase 3: OTEL spans para cada tool call — `tracing::info_span!("agent.tool_call", ...)` com todos os atributos do spec; `tracing_opentelemetry::layer()` integrado ao subscriber; upgrade opentelemetry 0.25 → 0.26; zero-crash se endpoint não configurado.
- [x] Fase 4: MCP wrapper crate — HTTP proxy que mede tools/list e tools/call, envia métricas (bytes, duração, SHA256, erro) ao collector, passa-through de outros métodos.
- [x] Fase 5: Testes de integração automatizados (20 testes: 7 unit + 8 api + 5 proxy).
- [x] T-225: docs/agent-meter-otel.md + scripts/smoke-otel.sh
- [ ] T-225: ConfigMap OTEL no deploy do collector
- [ ] T-229: Dashboard UI melhorada (Vite+Preact)
- [x] T-226: Antigravity integration — universal script + skill
- [x] T-227: Copilot/VSCode integration — universal script + skill + MCP wrapper
- [x] T-228: Cursor integration — universal script + skill + MCP wrapper
- [x] Criar skill OTEL/integration reutilizável para todos os agentes (`.agents/skills/agent-meter-integration/`)
