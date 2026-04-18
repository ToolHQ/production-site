# T-129: Observability Report Modularization and API Readiness

- **Status**: In Progress
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

---

## Tasks

### Fase 1 — mapear a arquitetura atual

- [/] Levantar entrypoints, responsabilidades e acoplamentos em `cluster_health_check.sh`, `generate_catalog.sh`, `generate_inventory_report.sh` e `k8s_ops_menu.sh`.
- [ ] Classificar cada trecho em: collector, normalizer, rules engine, renderer, transport, cache/snapshot e glue de TUI.
- [ ] Identificar dependências escondidas: `ssh`, `kubectl`, `jq`, diretórios de report, links `latest-*`, cores ANSI e assumptions de ambiente.
- [ ] Registrar quais contratos de saída já são consumidos hoje por TUI, HTML e markdown.

### Fase 2 — definir fronteiras testáveis

- [ ] Propor contratos canônicos para dois domínios: `health-report` e `inventory-catalog`.
- [ ] Definir claramente quais funções podem ser puras e quais devem permanecer como side effects de coleta.
- [ ] Separar o pipeline lógico em: `collect -> normalize -> evaluate -> render -> serve`.
- [ ] Identificar o menor conjunto inicial de extrações que já melhora testabilidade sem obrigar rewrite completo.

### Fase 3 — planejar a camada de testes

- [ ] Definir fixtures reprodutíveis a partir de `kubectl get ... -o json` e snapshots locais de `apps/` e `components/`.
- [ ] Definir testes unitários para regras e transformações puras.
- [ ] Definir testes de integração para collectors com cluster online e modo offline controlado.
- [ ] Definir testes de regressão comparando o output atual com os novos payloads estruturados.

### Fase 4 — desenhar a migração para API interna

- [ ] Comparar opções de runtime para o backend sob restrição real de CPU/memória e operação: shell + adapter, Python, Node, Go.
- [ ] Definir a recomendação de arquitetura para uma API interna simples, estável e barata de operar.
- [ ] Definir como o frontend futuro vai consumir esses contratos sem depender do filesystem local ou da TUI.
- [ ] Propor rollout em fases: estabilizar contrato JSON, extrair domínio reutilizável, adicionar API, então anexar UI web mantendo a TUI como fallback.

### Fase 5 — entregável de decisão

- [ ] Produzir um documento de arquitetura/ADR com fronteiras, riscos, trade-offs e ordem de implementação.
- [ ] Definir a primeira thin slice recomendada para a migração, preferencialmente reutilizando o `catalog.json` como base.
- [ ] Registrar o que fica explicitamente fora da primeira fase para evitar escopo inflado.

---

## Acceptance Criteria

- [ ] Existe um mapa claro das responsabilidades e acoplamentos dos relatórios atuais.
- [ ] Existe um contrato-alvo explícito para `health-report` e `inventory-catalog`.
- [ ] Existe estratégia de testes com fixtures e regressão definida.
- [ ] Existe recomendação técnica de backend/API compatível com o cluster atual.
- [ ] A migração proposta preserva a TUI durante a transição e evita rewrite big bang.

---

## References

- `oci-k8s-cluster/scripts/observability/cluster_health_check.sh`
- `oci-k8s-cluster/scripts/observability/generate_catalog.sh`
- `oci-k8s-cluster/scripts/observability/generate_inventory_report.sh`
- `oci-k8s-cluster/k8s_ops_menu.sh`
- `tasks/2026/Q2/T-102-Cluster-Health-Watchdog.md`
- `tasks/2026/Q2/T-110-Unified-Catalog-Inventory.md`
- `tasks/2026/Q2/T-111-Catalog-Enrichment.md`
