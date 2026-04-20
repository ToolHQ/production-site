# T-134: Observability Console Prometheus Time-Series

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: DevExp / Observability
- **Estimation**: 6h

## Context

O slice Rust em `apps/rs-observability-api` já deixou de ser apenas um servidor de snapshots: ele hoje
expõe catálogo, artefatos e um board vivo de saúde dos workloads críticos via Kubernetes API read-only.

Isso melhorou muito a utilidade operacional, mas ainda existe um gap óbvio em relação a ferramentas de
observabilidade mais maduras: faltam séries temporais reais para CPU, memória, restart pressure e sinais
contínuos por serviço.

### Estado atual

- `GET /api/live/overview` entrega estado instantâneo de serviços críticos e incidentes atuais.
- A UI em `apps/rs-observability-api/web/index.html` já foi redesenhada como console operacional.
- O cluster já possui Prometheus funcional dentro do namespace `coroot`, exposto pelo service
  `coroot-prometheus-server`.
- Teste manual confirmou que a API de query do Prometheus responde para `query` e `query_range`.
- O Prometheus do Coroot neste cluster expõe métricas de runtime por `container_resources_*` com labels
  `container_id` e `app_id`, não a família tradicional `container_*` com `namespace` e `pod`.

### Objetivo desta tarefa

Adicionar ao console Rust uma camada Prometheus-backed de séries temporais leves e baratas de manter,
sem introduzir banco novo, sem agente extra e sem explodir o custo operacional do cluster ARM64.

### Entrega esperada

- novo payload de métricas quase-real-time no backend Rust
- queries PromQL de baixo custo para sinais centrais do cluster
- sparklines/mini-charts na UI para CPU, memória e restart pressure
- breakdown por serviço crítico com consumo de CPU/memória recente
- deploy e validação funcionando no cluster via caminho OCI/Nexus atual

### Restrições

- manter filosofia `Stability First`
- evitar polling agressivo contra Prometheus
- preferir cache no backend em vez de lógica pesada no frontend
- manter footprint baixo do pod `rs-observability-api`

## Tasks

- [x] Confirmar que a API do Prometheus em `coroot-prometheus-server` responde para `query` e `query_range`
- [x] Definir o contrato JSON para métricas temporais dentro do console Rust
- [x] Implementar client Prometheus com cache próprio e refresh mais lento que o board instantâneo
- [x] Adicionar queries de cluster para CPU, memória e restart pressure
- [x] Adicionar queries por serviço crítico para CPU e memória recentes
- [x] Expor os dados na API do `rs-observability-api`
- [x] Atualizar a UI com charts leves e leitura operacional clara
- [x] Validar `cargo check`
- [x] Deployar no cluster com `deploy.sh`
- [x] Validar o payload exposto em `reports.dnor.io`
- [x] Marcar a tarefa e o KANBAN como concluídos após rollout estável

## Acceptance Criteria

- [x] O console expõe séries temporais reais vindas do Prometheus, não apenas snapshots de status
- [x] A UI mostra pelo menos CPU, memória e restart pressure do cluster
- [x] A UI mostra pelo menos CPU e memória recentes para os serviços críticos monitorados
- [x] O backend usa cache para evitar query storm no Prometheus
- [x] A entrega compila, sobe no cluster e responde corretamente em `reports.dnor.io`

## Resultado

- `GET /api/live/overview` agora entrega `metrics.cluster`, `metrics.services` e `metrics.top_restarts`
  com cache próprio e janela temporal de 60 minutos.
- O backend passou a consultar `node_resources_*` para CPU/memória do cluster e
  `container_resources_*` para CPU/memória por serviço, compatível com o Prometheus do Coroot.
- A UI foi reescrita para mostrar banda de métricas do cluster, sparklines por serviço, hotspots de
  restart, resumo operacional, catálogo deployable e biblioteca de artefatos na mesma página.
- O manifesto do deployment ganhou `PROMETHEUS_BASE_URL` explícito para fixar o alvo interno do
  Prometheus.

## Validação

- `cargo check` em `apps/rs-observability-api` concluído com sucesso.
- `deploy.sh` executado com rollout estável da imagem `1776714527`.
- `https://reports.dnor.io/api/live/overview` validado com:
  - CPU do cluster: `93.79%` / `3.75 cores`
  - memória do cluster: `54.47%`
  - séries por 6 serviços críticos com CPU e memória não zeradas
  - hotspots reais de restart em pods do Longhorn no último período

## References

- `apps/rs-observability-api/src/main.rs`
- `apps/rs-observability-api/web/index.html`
- `apps/rs-observability-api/k8s/rs-observability-api.yaml`
- `tasks/2026/Q2/T-133-Rust-Observability-API-Thin-Slice.md`
- `tasks/2026/Q2/T-129-Observability-Report-Modularization-and-API-Readiness.md`
