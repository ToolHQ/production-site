# T-328: Fleet Copilot — smoke E2E Playwright no reports

- **Status**: Backlog
- **Priority**: 🔵 Medium
- **Owner**: Cursor / AI Radar
- **Epic**: Fleet Copilot (T-315)
- **Est**: 6h
- **Depends on**: T-323, harness shell existente
- **Blocks**: Nenhum

## Context

Hoje: `scripts/harness/validate_fleet_copilot.sh` (curl/ssh). Falta regressão de UI (nav Copilot, locked → login mock, preset click).

## Escopo

- [ ] Playwright em `apps/rs-observability-api/web-v2` ou `scripts/harness/`
- [ ] Mock `GET /api/fleet/copilot/session` + stream SSE fixture
- [ ] CI job opcional (não bloquear PR se reports offline)
- [ ] Documentar `FLEET_COPILOT_LOGIN_KEY` via secret em CI staging

## Critérios de aceite

- [ ] `npm run test:e2e` (ou script) passa local com mocks
- [ ] Cobre `#fleet-copilot` nav + locked card + 1 preset

## Referências

- `scripts/harness/validate_fleet_copilot.sh`
- [T-323c](T-323-Fleet-Copilot-UI-Reports.md)
