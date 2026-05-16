# T-173: AI Radar — Hardening

- **Status**: In Progress
- **Priority**: 🔽 Low
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 1d
- **Opened**: 2026-05-01

## Context

Endurecimento final: retries com backoff, timeouts globais, limites de tamanho/concorrência, sanitização HTML, idempotência reforçada, reprocessamento manual versionado, e bateria de **testes de falha estilo chaos** (RSS quebrado, LLM timeout, Postgres caindo, conteúdo gigante).

Fecha o ciclo de qualidade do MVP. Posiciona o sistema para operar autônomo no cluster por semanas sem intervenção.

## Tasks

- [x] Wrapper `with_retry(op, policy)` em `util/retry.rs` com `RetryPolicy::http_default()` + `RetryDirective` — RSS refatorado para usar `with_retry`
- [x] Jitter ±20% para evitar thundering herd
- [x] Aplicar wrapper em call sites HTTP externos — _RSS via `with_retry`; LLM usa `RetryingLlmProvider` (T-164)_
- [ ] GitHub/Web collectors (T-162/T-163) quando existirem
- [x] `limits.rs` centralizando: `MAX_RAW_CONTENT_BYTES=200_000`, `MAX_EXTRACT_INPUT_TOKENS=8000`, `MAX_CONCURRENT_LLM_REQUESTS=2` _(RSS honra `MAX_RAW_CONTENT_BYTES`; extract/LLM ainda por T-164/T-165)_
- [x] Honrar `sources.poll_interval_minutes`: skipar source com `last_polled_at` recente _(batch collect; `--source-id` força)_
- [x] _Sem migration `0005`_ — `extracted_items.version` já existe em `0002`; scores usam histórico via `0003`
- [x] `POST /items/:id/reprocess` com `{ "stage": "extract"|"score"|"all" }` (síncrono MVP)
- [x] CLI `ai-radar reprocess --item <id> --stage all`
- [x] Reprocess extract gera **nova versão** (`insert` com `version: None` → `MAX+1`)
- [ ] Sanitização HTML defensiva (remover javascript: URIs, on* handlers em casos extremos)
- [x] Bateria de chaos tests em `crates/ai-radar-core/tests/chaos.rs` (slice):
  - [x] RSS source retorna 500 → outras OK _( `parallel_rss_collect.rs` )_
  - [x] LLM timeout → [`LlmError::Timeout`] sem panic _(unit em `chaos.rs`)_
  - [ ] Postgres derruba conexão → erro claro, sem panic
  - [x] Conteúdo >200KB → rejected, métrica incrementada _(RSS + `ai_radar_entries_rejected_total`)_
  - [ ] Múltiplos collects paralelos → zero duplicatas
- [x] Documentar "Failure modes" no README (quais falhas são esperadas, como debugar) _(secção curta + métricas)_

## DoD

- Sistema não panica em nenhum dos cenários chaos.
- Sistema não duplica dados sob concorrência.
- Sistema não consome memória sem limite (cap respeitado).
- Reprocess gera versões; antigas preservadas.
- Polling interval respeitado.
- Coverage chaos tests ≥85%.

## Validação

```bash
cd apps/ai-radar
cargo test -p ai-radar-core --test chaos -- --include-ignored

# Reprocess manual
ITEM_ID=$(psql $DATABASE_URL -tAc "SELECT id FROM ai_radar.extracted_items LIMIT 1")
curl -X POST localhost:8080/items/$ITEM_ID/reprocess -d '{"stage":"all"}'
psql $DATABASE_URL -c "SELECT version, count(*) FROM ai_radar.extracted_items WHERE id IN (SELECT id FROM ai_radar.extracted_items WHERE raw_item_id IN (SELECT raw_item_id FROM ai_radar.extracted_items WHERE id=$ITEM_ID)) GROUP BY version"

# Stress test (tamanho limite)
echo "<html>$(yes 'x' | head -c 300000)</html>" > /tmp/big.html
# inserir como source webpage e validar rejeição
```

## References

- `docs/AI-RADAR-DECISIONS.md` — riscos transversais e mitigações
- `docs/AI-RADAR-ROADMAP.md` — Fase 15
- Depende de: **T-172**
- Branch sugerida: `feat/T-173-ai-radar-hardening`
