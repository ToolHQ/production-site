# T-155: React-Static Toolchain Security Migration

- **Status**: In Progress
- **Priority**: 🚨 Critical
- **Epic/Owner**: Security / Frontend
- **Estimation**: 2d

## Context
Após o merge da PR #35 (T-154 Onda 1) e abertura da PR #36 (T-154 Onda 2 lote 1),
o `apps/react-static` permaneceu com backlog crítico de vulnerabilidades Dependabot.

Evidência objetiva levantada em 2026-04-26:

- `apps/react-static` com 59 vulnerabilidades abertas via `npm audit`
	- 1 critical
	- 28 high
	- 16 moderate
	- 14 low
- Grande parte da superfície está ancorada em cadeia legacy do `react-scripts@5.0.1`,
  exigindo upgrade de toolchain e/ou migração para stack mais atual.

Restrições operacionais:

- Ambiente `Stability First`: não fazer migração big-bang.
- Preferir rollout em duas etapas:
	1. endurecimento sem troca de framework de build (quando possível)
	2. migração de toolchain com validação funcional e rollback explícito

Arquivos-chave:

- `apps/react-static/package.json`
- `apps/react-static/package-lock.json`
- `.github/workflows/quality-gates.yml`
- `tasks/2026/Q2/T-154-Dependabot-Security-Remediation-Program.md`

## Tasks
- [x] Consolidar baseline de vulnerabilidades e classificar por severidade
- [x] Registrar task dedicada em In Progress no KANBAN
- [ ] Mapear estratégia alvo de toolchain (react-scripts hardening vs migração para Vite)
- [ ] Prototipar atualização mínima segura em branch (sem quebrar build)
- [ ] Executar validação local: `npm run typecheck`, `npm run build`, `npm run test:ci`
- [ ] Ajustar gate de CI para garantir cobertura do escopo alterado
- [ ] Medir redução de vulnerabilidades pós-ajustes e documentar residual
- [ ] Abrir PR da T-155 com plano de rollout + rollback
