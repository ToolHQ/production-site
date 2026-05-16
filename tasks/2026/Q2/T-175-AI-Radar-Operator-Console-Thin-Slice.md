# T-175: AI Radar — Operator Console (thin slice)

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 6h

## Context

O pipeline backend (collect → extract → score → digest) está no cluster, mas **não há superfície visual**: `https://ai-radar.dnor.io/` redireciona para JSON em `/health`. Stakeholders não conseguem “ver” o produto.

Esta task entrega a **Fase 16B** do [`docs/AI-RADAR-ROADMAP.md`](../../../docs/AI-RADAR-ROADMAP.md): console estático servido pelo mesmo binário `ai-radar-api` (padrão `rs-observability-api` / T-133), consumindo APIs existentes sem duplicar regras de negócio.

## Tasks

- [x] Assets embutidos (`include_dir`) em `crates/ai-radar-api/assets/`
- [x] Rotas UI: `/`, `/assets/app.{css,js}` (SPA hash: `#/`, `#/digests`, `#/digests/:id`, `#/sources`)
- [x] Home: cards de `GET /stats` + link para último digest
- [x] Lista `GET /digests` + viewer Markdown (`GET /digests/:id`, `Accept: text/markdown`)
- [x] Página sources (`GET /sources`)
- [x] Remover redirect `GET /` → `/health` (manter `/health` para probes)
- [x] Testes Axum: `/` retorna `text/html`; `/health` inalterado
- [x] README: console no browser
- [x] Deploy cluster tag `1778959644` + smoke visual em `https://ai-radar.dnor.io/`
- [ ] Runbook T-191: passo demo browser (atualizar após merge PR)

## DoD

- Abrir `https://ai-radar.dnor.io/` mostra estado do pipeline e digests legíveis sem `curl`.
- `cargo test -p ai-radar-api` e gate `rust-ai-radar` verdes.
- Sem pod extra; footprint dentro dos limits atuais do Deployment.

## Validação

```bash
cd apps/ai-radar
cargo test -p ai-radar-api
curl -fsS https://ai-radar.dnor.io/ | head
curl -fsS https://ai-radar.dnor.io/stats | jq
```

## References

- [`docs/AI-RADAR-ROADMAP.md`](../../../docs/AI-RADAR-ROADMAP.md) — Fase 16
- Depende de: **T-169**, **T-172**, **T-174**
- Branch: `feat/T-175-ai-radar-operator-console`
