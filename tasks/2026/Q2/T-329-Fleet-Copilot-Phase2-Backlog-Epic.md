# T-329: Fleet Copilot — Epic fase 2 (polish + hardening)

- **Status**: Done (core T-327–335 entregues 2026-05-31)
- **Priority**: 🔵 Medium
- **Owner**: Cursor / AI Radar
- **Epic**: Fleet Copilot pós-MVP
- **Est**: ~1–2 semanas (parcelado)
- **Depends on**: T-315 MVP Done

## Itens fase 2 — entregues

| ID | Nome | Status |
|----|------|--------|
| T-332 | Manifesto fleet no contexto LLM | Done |
| T-333 | Multi-node OCI + external fleet | Done |
| T-334 | Intent routing + qualidade modelo | Done |
| T-335 | Structured replies / Gemma bypass | Done |
| T-327 | Loading UX inferência lenta | Done |
| T-328 | Playwright E2E smoke | Done |

## Backlog fase 3 (fora deste epic)

| ID | Nome |
|----|------|
| T-324 | Hermes Agent opcional |
| T-322e | Audit log Postgres |
| T-321 backlog | ~~Gateway kubeconfig view-only~~ Done 2026-06-01 |
| T-331 | SSH alias canônico |
| — | CI Playwright job |
| — | Histórico Postgres |

## Gate fase 2

- [x] Harness verde pós-deploy (T-332–335)
- [x] PR #375/#376 merged ou mergeable
- [x] Structured-first reduz dependência Gemma

## Referências

- [T-315](T-315-Fleet-Copilot-Epic-Overview.md)
- [KANBAN](../../KANBAN.md)
