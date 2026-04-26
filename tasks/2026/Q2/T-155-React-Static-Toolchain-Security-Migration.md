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
- [x] Mapear estratégia alvo de toolchain (react-scripts hardening vs migração para Vite)
- [x] Prototipar atualização mínima segura em branch (sem quebrar build)
- [x] Executar validação local: `npm run typecheck`, `npm run build`, `npm run test:ci`
- [x] Ajustar gate de CI para garantir cobertura do escopo alterado
- [x] Medir redução de vulnerabilidades pós-ajustes e documentar residual
- [/] Abrir PR da T-155 com plano de rollout + rollback

## Validação

### Fase 1 (hardening sem migração de toolchain)

Comandos executados:

- `cd apps/react-static && npm install --no-audit --no-fund`
- `cd apps/react-static && npm audit --json > /tmp/audit-react-before.json`
- `cd apps/react-static && npm audit fix`
- `cd apps/react-static && npm audit --json > /tmp/audit-react-after-fix.json`
- `cd apps/react-static && npm run typecheck`
- `cd apps/react-static && npm run build`
- `cd apps/react-static && npm run test:ci`

Resultado de segurança:

- antes: 59 vulnerabilidades (1 critical, 28 high, 16 moderate, 14 low)
- depois: 28 vulnerabilidades (0 critical, 14 high, 5 moderate, 9 low)

Leitura técnica:

- ganho imediato relevante sem usar `--force`
- residual majoritariamente associado à cadeia legacy de `react-scripts@5.0.1`
- próximos cortes de risco dependem de migração de toolchain (ex.: Vite) em rollout controlado

### Fase 2 (migração controlada para Vite/Vitest)

Mudanças estruturais:

- remoção de `react-scripts` do `apps/react-static/package.json`
- adoção de `vite`, `vitest`, `@vitejs/plugin-react` e `jsdom`
- atualização de `@types/node` para `^22.13.8`
- novo entrypoint em `apps/react-static/src/main.tsx`
- novo `apps/react-static/index.html`
- novo `apps/react-static/vite.config.ts`
- ajuste de setup de testes para `@testing-library/jest-dom/vitest`
- gate do CI atualizado para incluir `build` em `JS quality gates (react-static)`

Comandos de validação executados:

- `cd apps/react-static && npm install --no-audit --no-fund`
- `cd apps/react-static && npm run typecheck`
- `cd apps/react-static && npm run build`
- `cd apps/react-static && npm run test:ci`
- `cd apps/react-static && npm audit --json > /tmp/audit-react-phase2.json`

Resultado de segurança da fase 2:

- antes da migração: 28 vulnerabilidades (0 critical, 14 high, 5 moderate, 9 low)
- depois da migração: 5 vulnerabilidades (0 critical, 0 high, 5 moderate, 0 low)

Leitura técnica da fase 2:

- migração concluída com build/test/typecheck em `PASS`
- risco residual concentrado em versões moderadas de `vite`/`vitest` cuja correção disponível é major
