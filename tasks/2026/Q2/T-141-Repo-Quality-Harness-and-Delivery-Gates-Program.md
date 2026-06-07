# T-141: Repo Quality Harness & Delivery Gates Program

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: DevExp / Tooling
- **Estimation**: 1d

## Context
O repositório já tem bons sinais locais de qualidade, mas eles ainda estão dispersos por stack e sem um
contrato único de entrega. Hoje o cenário prático é este:

- `apps/rs-observability-api` já entrega valor operacional alto, porém ainda concentra muita lógica em
	`main.rs` e não possui trilha mínima de `cargo test`/`clippy`/`fmt --check` como gate obrigatório
- `apps/back-end` já possui `lint` e `build`, mas ainda falta separar `typecheck`, consolidar teste e
	encaixar isso num fluxo uniforme de entrega
- `oci-k8s-cluster` já usa BATS com bom padrão de teste para shell/TUI, mas isso ainda não foi elevado a
	política de harness transversal para scripts, manifests e deploy flows
- apps web e utilitários continuam heterogêneos: alguns têm build, outros têm teste, e quase nenhum está
	samarrado a uma regra única de `verify-changed` antes de concluir task

Como o cluster e a operação seguem a filosofia `Stability First`, o programa precisa ser seguro e leve:

- nada de adicionar plataforma pesada, SaaS novo ou pipeline caro para o estado atual do projeto
- gates devem ser rápidos, previsíveis e acionados por caminho alterado, não por varredura global toda vez
- rollout deve começar em modo observável/não-bloqueante e só virar obrigatório depois de estabilizado

### Arquivos centrais já confirmados

- [apps/rs-observability-api/Cargo.toml](/home/ToolHQ/production-site/apps/rs-observability-api/Cargo.toml)
- [apps/rs-observability-api/src/main.rs](/home/ToolHQ/production-site/apps/rs-observability-api/src/main.rs)
- [apps/back-end/package.json](/home/ToolHQ/production-site/apps/back-end/package.json)
- [apps/react-static/package.json](/home/ToolHQ/production-site/apps/react-static/package.json)
- [apps/static/package.json](/home/ToolHQ/production-site/apps/static/package.json)
- [oci-k8s-cluster/testing/k8s_ops_menu.bats](/home/ToolHQ/production-site/oci-k8s-cluster/testing/k8s_ops_menu.bats)
- [oci-k8s-cluster/run_tests.sh](/home/ToolHQ/production-site/oci-k8s-cluster/run_tests.sh)
- [tasks/KANBAN.md](/home/ToolHQ/production-site/tasks/KANBAN.md)

## Objetivos do programa

1. Criar um harness raiz único para validação local e em CI.
2. Garantir que toda task entregue rode checks mínimos por stack antes de fechar.
3. Impedir regressão silenciosa de qualidade, mesmo sem meta global rígida de cobertura no início.
4. Tornar validação barata e previsível em ambiente resource-constrained.
5. Evoluir por ratchet: primeiro consistência, depois profundidade.

## Não objetivos nesta fase

- implantar SonarCloud/Codecov SaaS ou plataforma analítica **paga**
- _(rescope T-341)_ SonarQube **CE self-hosted** no SSDNodes é permitido via [ADR-jenkins-sonarqube-colocation.md](../../components/ssdnodes/ADR-jenkins-sonarqube-colocation.md) — complementa o harness, não substitui gates leves
- criar suíte browser E2E completa para todo o sistema
- impor cobertura global do monorepo como gate inicial
- executar deploy real em cluster em toda alteração trivial de código

## Tasks

### Frente 0 — Baseline e contrato de entrega

- [x] Definir o contrato mínimo de entrega por stack (`verify-changed` obrigatório para fechar task)
- [x] Formalizar `Definition of Done` com evidência de validação local ou CI por alteração
- [x] Padronizar a seção `## Validação` nas tasks novas e relevantes
- [x] Levantar baseline inicial dos comandos válidos por stack antes de tornar qualquer gate bloqueante

### Frente 1 — Harness raiz do repositório

- [x] Criar runner raiz leve em `tools/harness/` com entradas `verify-changed`, `verify-all` e `smoke`
- [x] Implementar detector de caminhos alterados para selecionar checks por diretório afetado
- [x] Produzir saída curta, determinística e com códigos de saída confiáveis
- [x] Padronizar cache/local bootstrap para evitar reinstalação desnecessária de dependências

### Frente 2 — Rust / observability apps

- [x] Extrair o `rs-observability-api` em módulos testáveis (router, serviços, parsing, render decisions)
- [x] Introduzir `cargo fmt --check`, `cargo clippy -- -D warnings` e `cargo test` como gate base
- [x] Criar testes de contrato para `health`, endpoints JSON e artefatos HTML críticos
- [x] Definir smoke check opcional de deploy para endpoints críticos quando a task tocar fluxo publicado
- [x] Estender o padrão depois para `rs-axum-back-end`, `rs-rust-city` e `rs-vanilla-back-end`

### Frente 3 — Shell, TUI e manifests

- [x] Promover BATS atual a padrão oficial para shell scripts com comportamento crítico
- [x] Adicionar `shellcheck` e `shfmt` aos scripts e deploy helpers suportados
- [x] Introduzir `yamllint` com configuração conservadora e sem ruído excessivo
- [x] Validar manifests Kubernetes com `kubeconform` ou equivalente leve, preferindo renderização local
- [x] Separar smoke de cluster dos checks puramente locais para não bloquear edição simples

### Frente 4 — Node/TypeScript e front-end

- [x] Separar `typecheck`, `lint`, `test` e `build` onde hoje isso está acoplado ou ausente
- [x] Tornar `apps/back-end` validável sem depender implicitamente de deploy
- [x] Revisar `apps/react-static` para execução determinística de testes em modo CI
- [x] Criar trilha mínima para `apps/static` com `tsc --noEmit` e build gateado
- [x] Mapear quais apps merecem smoke HTTP/asset check adicional após build

### Frente 5 — CI e enforcement progressivo

- [x] Criar workflow path-aware para rodar apenas os checks relevantes ao diff
- [x] Iniciar em modo informativo por uma janela curta de estabilização
- [x] Elevar os checks maduros a required status checks por stack
- [x] Garantir logs curtos e legíveis para triagem rápida em PR/task
- [x] Evitar matrizes exageradas ou jobs pesados incompatíveis com o perfil do projeto

### Frente 6 — Ratchet e métricas úteis

- [x] Publicar resumo final por execução com comandos rodados, duração e falhas por categoria
- [x] Medir adoção do harness por task concluída
- [x] Definir ratchet de cobertura apenas por módulo que já tenha suíte estável
- [x] Impedir aumento de warnings conhecidos em vez de perseguir métrica global vazia

## Execution Notes (2026-04-26)

- O programa foi concluído como umbrella operacional através das tasks derivadas T-142 a T-148 e dos gates já versionados no repo.
- O harness raiz ativo está em `tools/harness/verify.sh`, com `verify-changed`, `verify-all` e `smoke` reservado.
- O detector path-aware está em `tools/harness/lib/changed_paths.sh`.
- O workflow de CI path-aware está ativo em `.github/workflows/quality-gates.yml`.
- O contrato de entrega foi formalizado na raiz do repo e no template de novas tasks:
	- `README.md`
	- `tools/manage_tasks.sh`
- A seção `## Validação` agora faz parte do esqueleto padrão de tasks novas.

## Validação

- `./tools/harness/verify.sh verify-changed --paths tools/manage_tasks.sh README.md`
- Resultado: `PASS` em `shell-syntax`, `shellcheck` e `shfmt`; demais gates corretamente `SKIP` por escopo.

## Closed

- Date: 2026-04-26
- Follow-ups operacionais continuam em tasks específicas por stack e higiene contínua do cluster.

## Frentes de implantação

### 1. Governança e Definition of Done

Entrega esperada:

- toda task concluída precisa conter uma seção `## Validação` com comando real executado
- `Done` sem evidência de validação deixa de ser aceitável para código, shell, manifest ou UI publicada
- para alteração em app deployável, o mínimo exigido é `verify-changed`; smoke de deploy entra quando a
	task afetar rota publicada, manifest, imagem ou contrato exposto

Critério de saída:

- nova regra documentada e aplicada de forma consistente em tasks subsequentes

### 2. Harness raiz path-aware

Entrega esperada:

- estrutura como `tools/harness/verify.sh`, `tools/harness/lib/changed_paths.sh` e perfis por stack
- suporte a dois modos:
	- `verify-changed`: rápido e focado no diff
	- `verify-all`: execução completa para auditoria ou endurecimento
- saída consolidada por bloco: `rust`, `node`, `shell`, `yaml`, `smoke`

Critério de saída:

- qualquer desenvolvedor consegue rodar um único comando na raiz e saber se a alteração está apta a seguir

### 3. Hardening do `rs-observability-api`

Entrega esperada:

- redução do acoplamento do `main.rs`
- testes de unidade para funções puras e testes de integração para rotas principais
- smoke simples para confirmar HTML/JSON essencial sem depender de inspeção manual em browser

Critério de saída:

- alterações em `apps/rs-observability-api/**` passam por `fmt`, `clippy`, `test` e smoke compatível

### 4. Hardening de shell/K8s/deploy

Entrega esperada:

- BATS ampliado para comandos críticos da TUI e flows de deploy/helpers
- `shellcheck`/`shfmt` nos scripts principais
- lint/validação de YAML sem introduzir ruído improdutivo em manifests legados não tocados

Critério de saída:

- qualquer alteração em `oci-k8s-cluster/**`, `components/**` ou `apps/*/deploy.sh` ativa checks locais

### 5. Hardening de Node/TypeScript

Entrega esperada:

- scripts explícitos para `lint`, `typecheck`, `test`, `build`
- remoção de dependência implícita de `build` para detectar erro de tipo tarde demais
- convergência mínima de naming/script contract entre apps JS/TS

Critério de saída:

- qualquer alteração em app JS/TS roda pelo menos lint + typecheck + teste/build compatível

### 6. CI enxuta e progressiva

Entrega esperada:

- workflow único ou conjunto curto de workflows por caminho alterado
- modo warning-only inicial e posterior promoção para gate obrigatório
- cache moderado para `cargo`, `npm` e utilitários de lint

Critério de saída:

- PR ou task branch relevante recebe feedback automático coerente com o harness local

### 7. Ratchet de qualidade

Entrega esperada:

- baseline explícita de warnings e cobertura onde existir suíte madura
- proibição de regressão nos módulos já estabilizados
- scorecard final orientado a decisão, não a vanity metrics

Critério de saída:

- qualidade não piora entre entregas consecutivas nos módulos já enquadrados

## Matriz inicial de gates por stack

### Rust

- `cargo fmt --check`
- `cargo clippy --all-targets --all-features -- -D warnings`
- `cargo test`
- smoke HTTP opcional para apps publicados

### Node/TypeScript

- `npm run lint`
- `npm run typecheck`
- `npm test -- --watch=false` ou equivalente CI
- `npm run build` quando o artefato final fizer parte do contrato

### Shell / Bash

- `shellcheck`
- `shfmt -d`
- `./testing/bats testing/*.bats` onde existir suíte BATS

### YAML / Kubernetes

- `yamllint`
- `kubeconform` em manifests renderizados ou selecionados

### Deploy / smoke

- `curl`/probe textual para endpoints críticos
- validação de rollout apenas para alterações que impactem publicação real

## Faseamento seguro

### Fase 0 — Inventário e modo observável

Escopo:

- levantar comandos reais por stack
- identificar gaps e falsos positivos
- ainda sem bloquear merges/fechamento por tool noise desconhecido

Saída:

- baseline validada e backlog de correções rápidas dos próprios checks

### Fase 1 — Harness local unificado

Escopo:

- criar `verify-changed` e `verify-all`
- integrar Rust inicial + shell/BATS já existente

Saída:

- fluxo local único já utilizável antes de qualquer CI obrigatória

### Fase 2 — `rs-observability-api` como piloto

Escopo:

- modularização mínima para testabilidade
- testes de contrato e smoke baratos

Saída:

- primeira vertical completa do programa em um app de alto valor

### Fase 3 — Shell/K8s e deploy flows

Escopo:

- endurecer scripts operacionais, manifests e deploy helpers

Saída:

- redução de regressões em automação e configuração

### Fase 4 — Node/TS

Escopo:

- convergir contratos de script e checks nas apps JS/TS

Saída:

- gate consistente para back-end TS e front-ends relevantes

### Fase 5 — CI obrigatória por stack madura

Escopo:

- subir workflow path-aware
- promover apenas checks já estáveis a bloqueantes

Saída:

- PR feedback automático sem custo operacional desnecessário

### Fase 6 — Ratchet e ampliação controlada

Escopo:

- ampliar cobertura e endurecer thresholds somente nos módulos já limpos

Saída:

- qualidade acumulativa, não pontual

## Definition of Done proposta

Uma task técnica só pode ser fechada quando:

1. O escopo alterado passa no `verify-changed` correspondente.
2. A task registra evidência objetiva em `## Validação`.
3. Se houve mudança de contrato exposto, existe teste ou smoke check correspondente.
4. Não foram introduzidos warnings novos nos gates já maduros.
5. O KANBAN e o task file refletem o estado real da entrega.

## Riscos e mitigação

### Risco 1 — Harness virar pesado demais

Mitigação:

- path filter por diretório
- smoke separado de lint/test local
- nada de serviços adicionais persistentes

### Risco 2 — Ruído demais em legados

Mitigação:

- ratchet por área tocada
- modo informativo inicial
- bloquear apenas checks maduros

### Risco 3 — Acoplamento entre deploy e validação local

Mitigação:

- separar claramente `verify` de `smoke-deploy`
- manter deploy real só para mudanças que afetem publicação/infra

### Risco 4 — Custos de manutenção dos checks

Mitigação:

- poucas ferramentas, bem escolhidas
- scripts raiz curtos e sem framework interno complexo

## Métricas de sucesso

- `verify-changed` verde passa a acompanhar toda task concluída de código
- tempo mediano do `verify-changed` fica em faixa operacional aceitável
- redução de regressões pós-entrega em scripts, rotas e UI publicada
- aumento gradual do número de módulos cobertos por gates obrigatórios

## Ordem recomendada de execução real

1. Implementar o harness raiz mínimo.
2. Fechar o piloto completo no `rs-observability-api`.
3. Endurecer shell/TUI/manifests.
4. Convergir `apps/back-end`, `apps/static` e `apps/react-static`.
5. Ligar CI path-aware.
6. Só então introduzir ratchet de cobertura e thresholds adicionais.

## Próximas tasks recomendadas após aprovação

- T-142: Harness raiz `verify-changed` + `verify-all`
- T-143: `rs-observability-api` modularization for testability
- T-144: Shell/TUI quality gates (`BATS` + `shellcheck` + `shfmt`)
- T-145: JS/TS script convergence (`lint` + `typecheck` + `test`)
- T-146: CI path-aware required checks rollout

## Resultado esperado do programa

Ao final, cada entrega deixa de depender de memória tácita do operador sobre “o que precisava testar” e
passa a obedecer um contrato explícito, barato e reproduzível. O ganho principal não é só cobertura: é
redução de regressão operacional e previsibilidade de entrega num repositório poliglota e sensível como este.