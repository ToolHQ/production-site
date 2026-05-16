# T-135: Observability Console Operations-First UX Refactor

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: DevExp / Observability
- **Estimation**: 6h

## Context

O console em `apps/rs-observability-api` já evoluiu bastante: hoje ele entrega catálogo, artefatos,
estado ao vivo via Kubernetes API e séries temporais leves via Prometheus em uma única superfície.

Essa ampliação de escopo aumentou a utilidade do produto, mas também deixou a home tentando fazer
duas funções ao mesmo tempo:

- cockpit operacional para triagem rápida
- portal de inventário/catalog para builders

A auditoria em `reports/ui-ux-audit-reports-dnor-20260420.md` confirmou os principais gaps:

- primeira dobra ainda editorial demais para um console operacional
- incidentes e restart hotspots sem peso visual suficiente
- headline de saúde otimista demais em alguns cenários
- semântica de frescor distribuída, porém ainda cognitivamente cara
- telemetria bonita, mas pouco orientada a decisão
- catálogo e artifact library competindo com estado operacional na área nobre

### Objetivo desta tarefa

Transformar a home em uma experiência explicitamente `operations-first`, preservando a leveza do
frontend estático e sem depender de novos endpoints para a primeira iteração.

### Estratégia

- comprimir o hero em um header mais utilitário
- mover incidentes, restart hotspots e próximos riscos para a zona primária
- tornar o resumo executivo coerente com os sinais visíveis na própria tela
- deixar claro, por módulo, o frescor e a origem dos dados
- empurrar catálogo e artefatos para uma faixa secundária da home
- melhorar semântica visual de severidade e de ação sem inflar o custo do pod

### Restrições

- manter a filosofia `Stability First`
- evitar dependência de bibliotecas pesadas no frontend
- não criar polling extra ou lógica cara no browser
- manter o deploy compatível com o fluxo OCI/Nexus atual

### Arquivos centrais

- `apps/rs-observability-api/web/index.html`
- `apps/rs-observability-api/src/main.rs`
- `reports/ui-ux-audit-reports-dnor-20260420.md`

## Tasks

- [x] Abrir a tarefa oficial no fluxo do KANBAN e mover para `In Progress`
- [x] Consolidar o backlog aplicado a partir da auditoria de UI/UX
- [x] Redesenhar a primeira dobra para foco operacional imediato
- [x] Reorganizar a hierarquia principal da página para priorizar incidentes e hotspots
- [x] Ajustar a lógica de headline e resumo de saúde para reduzir otimismo indevido
- [x] Reforçar semântica de frescor, severidade e próxima ação na UI
- [x] Rebaixar catálogo e artifact library para papel secundário na home
- [x] Corrigir semântica de contadores operacionais e pequenos débitos de acabamento
- [x] Validar HTML/erros do frontend
- [x] Validar `cargo check` se houver impacto contratual do frontend/backend
- [x] Publicar no cluster com `deploy.sh` e verificar `reports.dnor.io`
- [x] Marcar a tarefa e o KANBAN como concluídos após rollout estável

## Resultado

- a home de `apps/rs-observability-api/web/index.html` foi reescrita em um layout explicitamente
	`operations-first`
- o topo agora comunica watchpoints, próxima ação e sinais de frescor sem depender de leitura de catálogo
- incidentes ativos e restart debt foram promovidos para a zona primária da interface
- catálogo, deployable surface e artifact library foram deslocados para uma superfície secundária
- a lógica do headline deixou de comunicar estabilidade simplista e passou a refletir incidentes,
	degraded state, stale cache e restart pressure
- contadores operacionais de restart passaram a ser arredondados para leitura discreta
- a interface ganhou meta description e revisão textual para reduzir framing editorial na home

## Validação

- `cargo check` em `apps/rs-observability-api` concluído com sucesso
- `deploy.sh` executado com rollout estável do `rs-observability-api-deployment`
- `https://reports.dnor.io/` respondeu `HTTP 200` após o deploy
- `https://reports.dnor.io/api/live/overview` continuou respondendo JSON coerente com `available: true`
- screenshots pós-rollout capturados em:
	- `/home/ToolHQ/production-site/tmp/ui-audit/reports-desktop-postrefactor-loaded.png`
	- `/home/ToolHQ/production-site/tmp/ui-audit/reports-mobile-postrefactor-loaded.png`
