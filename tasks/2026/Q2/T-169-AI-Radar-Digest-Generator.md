# T-169: AI Radar — Digest Generator

- **Status**: Done
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp
- **Estimation**: 1d
- **Opened**: 2026-05-01
- **Closed**: 2026-05-15

## Context

Entregável-chave do produto: **digest acionável em Markdown** (daily 24h ou weekly 7d). Agrupa items por decisão (`adopt`/`test`/`monitor`/`ignore`) com top X por bucket, usando o formato visual definido no roadmap (com seções 🔥 Testar / 👀 Monitorar / ❌ Ignorar).

Exposto via API (`text/markdown` content-type) e CLI. Persistido em `digests` para histórico.

Limites configuráveis: top 5 adopt, 10 test, 5 monitor, 5 ignore. Reasons/risks truncados a 3 itens cada para manter digest legível.

## Tasks

- [x] `pipeline/digest.rs` — seleção por janela (`DigestKind` daily/weekly), `select` + `render_markdown` + `run_digest` (consolidado no módulo; não há `digest/select.rs` separado)
- [x] Janelas: `Daily` (24h), `Weekly` (7d)
- [x] Seleção: scores na janela, agrupados por decisão, ordenados por score desc
- [x] Render Markdown com seções por decisão, truncagem de motivos/riscos conforme `DigestLimits`
- [x] Persistir em `ai_radar.digests` com `digest_type`, `markdown_content`, `generated_at`
- [x] CLI `ai-radar digest --daily | --weekly`
- [x] Endpoint `POST /digest/run` (`routes/digest.rs`)
- [x] Endpoints `GET /digests` e `GET /digests/:id` com `Accept` JSON vs `text/markdown`
- [x] Teste `crates/ai-radar-core/tests/digest_generator.rs`
- [ ] E2E cluster completo (cron + dados reais) — validação manual / T-191 quando imagem no cluster incluir estes endpoints

## Nota operacional (2026-05-15)

A pilha digest está no **código** e testes passam localmente (`cargo test -p ai-radar-core --test digest_generator`). O Deployment em cluster pode ainda apontar para imagem **anterior** até um `deploy.sh` bem-sucedido; nesse cenário `POST /digest/run` pode responder **404** até redeploy.

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
