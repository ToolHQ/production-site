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
- [ ] Definir estratégia por onda com ordem de execução e risco
- [ ] Aplicar onda 1: atualizações de baixo risco (patch/minor) em ferramentas e CI
- [ ] Validar onda 1 com harness/checks relevantes
- [ ] Aplicar onda 2: bibliotecas de aplicação com impacto funcional moderado
- [ ] Validar onda 2 com testes/gates por stack
- [ ] Aplicar onda 3: upgrades major necessários com plano de compatibilidade
- [ ] Registrar exceções justificadas (quando upgrade não for viável imediato)
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
