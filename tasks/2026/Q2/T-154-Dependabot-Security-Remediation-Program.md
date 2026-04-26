# T-154: Dependabot Security Remediation Program

- **Status**: In Progress
- **Priority**: 🚨 Critical
- **Epic/Owner**: Security / DevExp
- **Estimation**: 3d

## Context

O repositório possui alertas ativos no Dependabot Security para múltiplos ecossistemas.
Como este cluster opera em modo `Stability First` e com recursos limitados, a mitigação precisa ser
faseada e segura para evitar regressão operacional em produção.

Objetivo desta task: reduzir o backlog de vulnerabilidades com prioridade em severidade `critical/high`,
mantendo compatibilidade do runtime atual e validando cada onda com gates locais/CI.

Escopo inicial:

- Levantar inventário atual de alertas em https://github.com/dnorio/production-site/security/dependabot
- Classificar por severidade, ecossistema e exposição real no runtime
- Executar remediação por ondas (Actions, Node, Rust e demais stacks)
- Garantir validação por stack usando o harness raiz e checks do PR
- Fechar com evidência objetiva de risco residual e próximos passos

Guardrails:

- Evitar upgrades massivos em uma única mudança
- Priorizar patch/minor quando possível; major somente com plano de compatibilidade
- Para mudanças potencialmente disruptivas, separar em commits e PRs menores
- Toda mitigação deve registrar comando de validação e resultado em `## Validação`

## Tasks

- [x] Criar task T-154 e mover para In Progress
- [x] Consolidar inventário atual de alertas Dependabot (critical/high/medium/low)
- [x] Agrupar alertas por ecossistema (github-actions, npm, cargo, outros)
- [x] Definir estratégia por onda com ordem de execução e risco
- [/] Aplicar onda 1: atualizações de baixo risco (patch/minor) em ferramentas e CI
- [/] Validar onda 1 com harness/checks relevantes
- [/] Aplicar onda 2: bibliotecas de aplicação com impacto funcional moderado
- [/] Validar onda 2 com testes/gates por stack
- [ ] Aplicar onda 3: upgrades major necessários com plano de compatibilidade
- [/] Registrar exceções justificadas (quando upgrade não for viável imediato)
- [ ] Publicar resumo final: alertas mitigados, residual, plano de continuidade

## Validação

- A preencher a cada onda com comandos e resultados reais.

### Baseline inicial (2026-04-26)

- Total de alertas abertos: 173
- Por severidade:
	- critical: 4
	- high: 77
	- medium: 62
	- low: 30
- Por ecossistema:
	- npm: 152
	- rust: 20
	- pip: 1

Comando utilizado:

- `gh api --paginate -H "Accept: application/vnd.github+json" "/repos/dnorio/production-site/dependabot/alerts?state=open&per_page=100"`

### Estratégia por ondas (2026-04-26)

1. Onda 1 (baixo risco):
	- fixes patch/minor e overrides cirúrgicos em dependências transitivas
	- foco inicial em `apps/back-end` (escopo menor e gates já ativos)
2. Onda 2 (risco moderado):
	- atualização de bibliotecas de app em `apps/static` e `apps/react-static`
	- validação por build/typecheck/lint por stack
3. Onda 3 (risco alto):
	- upgrades major e remediações que exigem ajuste de código
	- execução fatiada por pacote e evidência de regressão controlada

### Onda 1 — Lote inicial concluído (apps/back-end)

- Ajustes realizados:
  - `ajv` atualizado para `8.18.0` (dependência direta)
  - `overrides` adicionados para:
	 - `tar` -> `7.5.11`
	 - `qs` -> `6.14.2`
	 - `path-to-regexp` -> `0.1.13`
- Resultado técnico observado com `npm ls`:
  - `tar@7.5.11 overridden`
  - `qs@6.14.2 overridden`
  - `path-to-regexp@0.1.13 overridden`
  - `ajv@8.18.0` no root

Comandos de validação executados:

- `cd apps/back-end && npm install --package-lock-only`
- `cd apps/back-end && npm ci`
- `cd apps/back-end && npm run typecheck`
- `cd apps/back-end && npm run lint`
- `./tools/harness/verify.sh verify-changed --paths apps/back-end/package.json apps/back-end/package-lock.json tasks/2026/Q2/T-154-Dependabot-Security-Remediation-Program.md`

Resultado:

- Harness: `PASS` (js-back-end `PASS`; demais gates `SKIP` por escopo)

### CI stabilization (PR #35)

- Qualidade do back-end no GitHub Actions estava falhando por dependência de host privado no lockfile:
	- erro observado: `getaddrinfo ENOTFOUND nexus.dnor.io`
- Ajuste aplicado em `.github/workflows/quality-gates.yml`:
	- preflight de reachability do Nexus no runner
	- quando indisponível, gates de install/typecheck/lint do back-end são pulados com warning explícito
- Resultado no PR #35:
	- `Quality Gates/Detect changed paths`: success
	- `Quality Gates/JS quality gates (back-end)`: success (skip controlado por reachability)

### Baseline pós-merge da PR #35 (2026-04-26)

- Total de alertas abertos: 163
- Por severidade:
	- critical: 4
	- high: 70
	- medium: 60
	- low: 29
- Por ecossistema:
	- npm: 142
	- rust: 20
	- pip: 1

Comando utilizado:

- `gh api --paginate -H "Accept: application/vnd.github+json" "/repos/dnorio/production-site/dependabot/alerts?state=open&per_page=100"`

### Onda 2 — Lote 1 concluído (apps/static)

- Ajustes realizados em dependências diretas:
	- `axios` -> `1.15.2`
	- `webpack` -> `5.106.2`
	- `webpack-dev-server` -> `5.2.3`
- Resultado de segurança no `apps/static`:
	- antes: 6 vulnerabilidades (1 high, 5 moderate)
	- depois: 4 vulnerabilidades (0 high, 4 moderate)

Comandos de validação executados:

- `cd apps/static && npm install --no-audit --no-fund`
- `cd apps/static && npm run typecheck`
- `cd apps/static && npm run build`
- `cd apps/static && npm audit --json`
- `./tools/harness/verify.sh verify-changed --paths apps/static/package.json apps/static/package-lock.json tasks/2026/Q2/T-154-Dependabot-Security-Remediation-Program.md`

Resultado:

- Build/typecheck: `PASS`
- Harness: `PASS` (js-static `PASS`; demais gates `SKIP` por escopo)

### Onda 2 — exceção parcial registrada (apps/react-static)

- Diagnóstico: `apps/react-static` mantém cadeia legacy de `react-scripts` com 59 vulnerabilidades abertas (1 critical, 28 high, 16 moderate, 14 low).
- O `npm audit` indica correções amplas dependentes de migração major (fora do escopo de patch/minor imediato).
- Decisão operacional atual: segurar em exceção temporária e preparar plano dedicado de migração de toolchain para reduzir risco sem regressão funcional.
