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
- [ ] Fase 2: CLI `agent-meter` com comandos `task start/end`, `event tool-call`, `report`.
- [ ] Fase 3: OTEL spans para cada tool call (quando endpoint configurado).
- [ ] Fase 4: MCP wrapper crate (proxy medidor entre IDE/agent e MCP real).
- [ ] Fase 5: Testes de integração automatizados.
