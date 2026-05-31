# T-328: Fleet Copilot — smoke E2E Playwright no reports

- **Status**: Done
- **Priority**: 🔵 Medium
- **Owner**: Cursor / AI Radar
- **Epic**: Fleet Copilot (T-315)
- **Est**: 6h
- **Depends on**: T-323, harness shell existente
- **Blocks**: Nenhum

## Context

Hoje: `scripts/harness/validate_fleet_copilot.sh` (curl/ssh). Regressão de UI via Playwright com mocks SSE.

## Escopo

- [x] Playwright em `scripts/harness/e2e/`
- [x] Mock `GET /api/fleet/copilot/session` + stream SSE fixture
- [x] Runner: `scripts/harness/run_fleet_copilot_e2e.sh`
- [ ] CI job opcional (não bloquear PR se reports offline) — backlog infra

## Critérios de aceite

- [x] `bash scripts/harness/run_fleet_copilot_e2e.sh` passa local com mocks
- [x] Cobre `#fleet-copilot` locked card + mock chat SSE

## Referências

- `scripts/harness/validate_fleet_copilot.sh`
- [T-323c](T-323-Fleet-Copilot-UI-Reports.md)
