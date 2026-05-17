# T-177: AI Radar — Items API + Explorer UI

- **Status**: In Progress
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 1d

## Context

O roadmap original prevê `GET /items` e `GET /items/:id`; hoje só existe `POST /items/:id/reprocess` (**T-173**). O console (**T-175**) mostra digests e stats, mas não permite **drill-down por item scored**.

Esta task fecha a **Fase 16C**: API de listagem/detalhe + páginas UI (tabela por `decision`, score, categoria) + gancho para reprocess e, depois, feedback (**T-170**).

## Tasks

- [x] `GET /items` — paginação, filtros `decision`, `category`, ordenação por score
- [x] `GET /items/:id` — extracted row + último score + versões
- [x] Repos/query SQLx em `ai-radar-core`
- [x] UI `#/items` e `#/items/:id` no console (estender assets T-175)
- [x] Botão reprocess (chama API existente) com confirmação
- [ ] Testes integração API + smoke browser
- [x] Atualizar `docs/AI-RADAR-DECISIONS.md` (contratos API)

## DoD

- Lista de itens scored visível no browser com pelo menos 1 item de demo no cluster.
- Reprocess `stage=score` acionável da UI para um item.

## References

- Depende de: **T-175**, **T-166**, **T-173**
- Relacionado: **T-170** (feedback)
- Branch sugerida: `feat/T-177-ai-radar-items-explorer`
