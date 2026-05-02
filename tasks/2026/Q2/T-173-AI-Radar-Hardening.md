# T-173: AI Radar — Hardening

- **Status**: Backlog
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp
- **Estimation**: 1d
- **Opened**: 2026-05-01

## Context

Endurecimento final: retries com backoff, timeouts globais, limites de tamanho/concorrência, sanitização HTML, idempotência reforçada, reprocessamento manual versionado, e bateria de **testes de falha estilo chaos** (RSS quebrado, LLM timeout, Postgres caindo, conteúdo gigante).

Fecha o ciclo de qualidade do MVP. Posiciona o sistema para operar autônomo no cluster por semanas sem intervenção.

## Tasks

- [ ] Wrapper `with_retry(op, policy)` em `util/retry.rs` com policies tipadas: `LlmDefault`, `HttpDefault`, `GitHub` (respeita `Retry-After`)
- [ ] Jitter ±20% para evitar thundering herd
- [ ] Aplicar wrapper em todos os call sites externos (RSS, GitHub, Web, LLM)
- [ ] `limits.rs` centralizando: `MAX_RAW_CONTENT_BYTES=200_000`, `MAX_EXTRACT_INPUT_TOKENS=8000`, `MAX_CONCURRENT_LLM_REQUESTS=2`
- [ ] Honrar `sources.poll_interval_minutes`: skipar source com `last_polled_at` recente
- [ ] Migration `0005_versioning.up.sql` adicionando `version int NOT NULL DEFAULT 1` em `extracted_items` e `scores`
- [ ] Endpoint `POST /items/:id/reprocess { stage: "extract"|"score"|"all" }` enfileira reprocessamento síncrono no MVP
- [ ] CLI `ai-radar reprocess --item <id> --stage all`
- [ ] Reprocess gera **nova versão**, não substitui; queries de "latest" via `DISTINCT ON`
- [ ] Sanitização HTML defensiva (remover javascript: URIs, on* handlers em casos extremos)
- [ ] Bateria de chaos tests em `crates/ai-radar-core/tests/chaos.rs`:
  - [ ] RSS source retorna 500 → outras OK, exit 0
  - [ ] LLM timeout → `extract_failed`, raw_item permanece pra retry
  - [ ] Postgres derruba conexão → erro claro, sem panic
  - [ ] Conteúdo >200KB → rejected, métrica incrementada
  - [ ] Múltiplos collects paralelos → zero duplicatas
- [ ] Documentar "Failure modes" no README (quais falhas são esperadas, como debugar)

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
