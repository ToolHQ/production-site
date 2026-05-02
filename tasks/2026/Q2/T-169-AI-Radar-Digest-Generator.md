# T-169: AI Radar — Digest Generator

- **Status**: Backlog
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp
- **Estimation**: 1d
- **Opened**: 2026-05-01

## Context

Entregável-chave do produto: **digest acionável em Markdown** (daily 24h ou weekly 7d). Agrupa items por decisão (`adopt`/`test`/`monitor`/`ignore`) com top X por bucket, usando o formato visual definido no roadmap (com seções 🔥 Testar / 👀 Monitorar / ❌ Ignorar).

Exposto via API (`text/markdown` content-type) e CLI. Persistido em `digests` para histórico.

Limites configuráveis: top 5 adopt, 10 test, 5 monitor, 5 ignore. Reasons/risks truncados a 3 itens cada para manter digest legível.

## Tasks

- [ ] `digest/select.rs::select(window: DigestWindow) -> DigestData` (função pura)
- [ ] Janelas: `Daily` (24h), `Weekly` (7d)
- [ ] Seleção: scores criados na janela, agrupados por decisão, ordenados por score desc
- [ ] `digest/render.rs::render_markdown(data: &DigestData) -> String`
- [ ] Header com data, sections com emoji, item com nome/score/categoria/motivo/riscos/próximo passo/link
- [ ] Truncar reasons/risks longos (3 itens cada)
- [ ] `pipeline/digest.rs::run(kind: DigestKind)` orquestra select → render → persist
- [ ] Persistir em `digests` com `digest_type`, `markdown_content`, `generated_at`
- [ ] CLI `ai-radar digest --daily | --weekly`
- [ ] Endpoint `POST /digest/run`
- [ ] Endpoints `GET /digests` (lista) e `GET /digests/:id` (Content-Type via Accept: `application/json` ou `text/markdown`)
- [ ] Snapshot test com `DigestData` fixo
- [ ] E2E: collect → extract → score → digest, validar conteúdo

## DoD

- `ai-radar digest --weekly` gera Markdown e grava em `digests`.
- Markdown renderiza corretamente no GitHub preview.
- API serve com content-type adequado (text/markdown).
- Sem decisão repetida entre seções (item aparece em UMA bucket).
- E2E pipeline completo verde.
- Coverage ≥80%.

## Validação

```bash
cd apps/ai-radar
cargo run -p ai-radar-cli -- digest --weekly
psql $DATABASE_URL -c "SELECT digest_type, generated_at FROM ai_radar.digests ORDER BY generated_at DESC LIMIT 5"
curl -s -H 'Accept: text/markdown' localhost:8080/digests/<id> | head -80
curl -s localhost:8080/digests | jq

cargo test -p ai-radar-core --test digest_generator
```

## References

- `docs/AI-RADAR-DECISIONS.md`
- `docs/AI-RADAR-ROADMAP.md` — Fase 11 (formato detalhado)
- Depende de: **T-166** (caminho crítico até MVP)
- Branch sugerida: `feat/T-169-ai-radar-digest-generator`
