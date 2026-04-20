# T-129: Observability Report Modularization and API Readiness

- **Status**: Done
- **Priority**: 🔼 High
- **Owner**: DevExp / Infra
- **Est.**: 6h
- **Created**: 2026-04-18

---

## Context

Hoje os relatórios de operação já entregam valor, mas a arquitetura está acoplada demais à TUI e ao shell para a próxima etapa do produto.

### Estado atual

#### 1. Cluster Health Report

- O watchdog vive em `oci-k8s-cluster/scripts/observability/cluster_health_check.sh`.
- O script já tem alguns helpers pequenos (`report_ok`, `report_warn`, `report_crit`, `age_seconds`, `fmt_age`), mas a maior parte da lógica ainda está inline: coleta via `kubectl`, regras de saúde, thresholds, renderização colorida e semântica de exit code no mesmo arquivo.
- A TUI chama esse relatório por SSH a partir de `oci-k8s-cluster/k8s_ops_menu.sh`, então o output já nasce preso ao terminal.

#### 2. Inventory & Catalog

- O catálogo em `oci-k8s-cluster/scripts/observability/generate_catalog.sh` já tem funções mais claras (`scan_apps`, `scan_components`, `scan_cluster`, `cross_reference`, `assemble_json`, `render_markdown`, `render_html`).
- Mesmo assim, coleta remota, parsing, enriquecimento, decisão semântica, geração dos artefatos e integração com a TUI continuam acoplados dentro do mesmo shell script.
- A TUI consome arquivos gerados em disco e o link `latest-catalog`, o que funciona para operação manual, mas não é um contrato de API.

#### 3. Storage Inventory legado

- `oci-k8s-cluster/scripts/observability/generate_inventory_report.sh` continua com coleta remota, temp files, SSH orchestration e renderização markdown/html fortemente entrelaçados.
- Isso reforça que hoje o “motor de report” ainda é um conjunto de scripts e não uma camada de domínio reaproveitável.

### Objetivo estratégico

Revisar e redesenhar os relatórios para funções bem encapsuladas, testáveis e com contratos estáveis, preparando uma futura migração para um backend/frontend rodando dentro do cluster, com dados em tempo real ou quase-real-time, sem ficar preso à TUI como única interface.

### Restrições de arquitetura

- Cluster ARM64, 1 vCPU / 6 GiB por nó.
- Filosofia `Stability First`: sem reinventar tudo, sem over-engineering e sem serviços pesados.
- A TUI atual continua sendo uma interface operacional útil e não deve ser quebrada durante a transição.

### Update 2026-04-18 — Deliverable concluído

- Foi produzido o ADR `oci-k8s-cluster/docs/OBSERVABILITY_API_MIGRATION_ADR.md` com:
  - mapa atual dos entrypoints e acoplamentos
  - fronteiras por camada (`collect -> normalize -> evaluate -> render -> serve`)
  - contratos canônicos para `health-report` e `inventory-catalog`
  - estratégia de testes por fixtures e regressão
  - comparação de runtime (`shell`, `Python`, `Node`, `Go`)
  - recomendação de thin slice: collectors shell + backend Python leve + SPA estática
  - rollout incremental preservando a TUI

### Update 2026-04-20 — Thin slice Rust implementada

- Foi implementado o serviço `apps/rs-observability-api`, um backend Axum mínimo em Rust que serve os artefatos já existentes em `reports/latest` e `reports/latest-catalog`.
- Endpoints expostos: `/health`, `/api/catalog`, `/api/catalog/summary`, `/api/reports` e `/artifacts/*path`.
- A raiz `/` entrega uma UI estática leve, também servida pelo próprio binário, para listar apps deployáveis e links para os artefatos HTML/Markdown/JSON.
- O deploy OCI/Nexus foi adicionado em `apps/rs-observability-api/deploy.sh` com manifesto Kubernetes próprio em `apps/rs-observability-api/k8s/rs-observability-api.yaml`.
- A implementação preserva a filosofia `Stability First`: sem banco novo, sem collector extra em runtime e com footprint de `10m/16Mi` de request e `50m/64Mi` de limit.

---

## Tasks

### Fase 1 — mapear a arquitetura atual

- [x] Levantar entrypoints, responsabilidades e acoplamentos em `cluster_health_check.sh`, `generate_catalog.sh`, `generate_inventory_report.sh` e `k8s_ops_menu.sh`.
- [x] Classificar cada trecho em: collector, normalizer, rules engine, renderer, transport, cache/snapshot e glue de TUI.
- [x] Identificar dependências escondidas: `ssh`, `kubectl`, `jq`, diretórios de report, links `latest-*`, cores ANSI e assumptions de ambiente.
- [x] Registrar quais contratos de saída já são consumidos hoje por TUI, HTML e markdown.

### Fase 2 — definir fronteiras testáveis

- [x] Propor contratos canônicos para dois domínios: `health-report` e `inventory-catalog`.
- [x] Definir claramente quais funções podem ser puras e quais devem permanecer como side effects de coleta.
- [x] Separar o pipeline lógico em: `collect -> normalize -> evaluate -> render -> serve`.
- [x] Identificar o menor conjunto inicial de extrações que já melhora testabilidade sem obrigar rewrite completo.

### Fase 3 — planejar a camada de testes

- [x] Definir fixtures reprodutíveis a partir de `kubectl get ... -o json` e snapshots locais de `apps/` e `components/`.
- [x] Definir testes unitários para regras e transformações puras.
- [x] Definir testes de integração para collectors com cluster online e modo offline controlado.
- [x] Definir testes de regressão comparando o output atual com os novos payloads estruturados.

### Fase 4 — desenhar a migração para API interna

- [x] Comparar opções de runtime para o backend sob restrição real de CPU/memória e operação: shell + adapter, Python, Node, Go.
- [x] Definir a recomendação de arquitetura para uma API interna simples, estável e barata de operar.
- [x] Definir como o frontend futuro vai consumir esses contratos sem depender do filesystem local ou da TUI.
- [x] Propor rollout em fases: estabilizar contrato JSON, extrair domínio reutilizável, adicionar API, então anexar UI web mantendo a TUI como fallback.

### Fase 5 — entregável de decisão

- [x] Produzir um documento de arquitetura/ADR com fronteiras, riscos, trade-offs e ordem de implementação.
- [x] Definir a primeira thin slice recomendada para a migração, preferencialmente reutilizando o `catalog.json` como base.
- [x] Registrar o que fica explicitamente fora da primeira fase para evitar escopo inflado.

---

## Acceptance Criteria

- [x] Existe um mapa claro das responsabilidades e acoplamentos dos relatórios atuais.
- [x] Existe um contrato-alvo explícito para `health-report` e `inventory-catalog`.
- [x] Existe estratégia de testes com fixtures e regressão definida.
- [x] Existe recomendação técnica de backend/API compatível com o cluster atual.
- [x] A migração proposta preserva a TUI durante a transição e evita rewrite big bang.

---

## References

- `oci-k8s-cluster/scripts/observability/cluster_health_check.sh`
- `oci-k8s-cluster/scripts/observability/generate_catalog.sh`
- `oci-k8s-cluster/scripts/observability/generate_inventory_report.sh`
- `oci-k8s-cluster/k8s_ops_menu.sh`
- `oci-k8s-cluster/docs/OBSERVABILITY_API_MIGRATION_ADR.md`
- `tasks/2026/Q2/T-102-Cluster-Health-Watchdog.md`
- `tasks/2026/Q2/T-110-Unified-Catalog-Inventory.md`
- `tasks/2026/Q2/T-111-Catalog-Enrichment.md`
