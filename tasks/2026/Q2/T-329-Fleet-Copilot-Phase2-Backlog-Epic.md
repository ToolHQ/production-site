# T-329: Fleet Copilot — Epic fase 2 (polish + hardening)

- **Status**: Backlog (índice)
- **Priority**: 🔵 Medium
- **Owner**: Cursor / AI Radar
- **Epic**: Fleet Copilot pós-MVP
- **Est**: ~1–2 semanas (parcelado)
- **Depends on**: T-315 MVP Done + ≥1 semana estável em prod

## Itens (backlog gerado 2026-05-31)

| ID | Nome | Prioridade |
|----|------|------------|
| T-324 | Hermes Agent opcional | Medium |
| T-326 | DNOR shell reading width (todas views) | Medium |
| T-327 | Loading UX inferência lenta | High |
| T-328 | Playwright E2E smoke | Medium |
| T-322e | Audit log Postgres (ver T-322) | High |
| T-320c | Alerta Prometheus SSH brute force | Medium |
| T-321 backlog | Gateway kubeconfig view-only + user `fleet-copilot` | High |
| — | Modelo menor/faster (qwen2.5:3b) A/B no monstro | Low |
| — | Histórico conversas (sessionStorage → Postgres) | Low |

## Gate fase 2

- [ ] Harness 8/8 verde por 7 dias
- [ ] Zero incidentes de abuse / rate limit
- [ ] PR #369+ merged (SSE flush + ultrawide)

## Referências

- [T-315](T-315-Fleet-Copilot-Epic-Overview.md)
- [KANBAN](../../KANBAN.md)
