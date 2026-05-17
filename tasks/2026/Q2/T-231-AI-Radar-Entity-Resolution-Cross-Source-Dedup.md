# T-231: AI Radar — Entity Resolution & Cross-Source Dedup

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 1d

## Context

Deduplicação atual: `UNIQUE (source_id, content_hash)` em `raw_items` — evita re-coleta na **mesma fonte**, mas o **mesmo produto** pode aparecer 3× (RSS HN + Lobsters + release GitHub) com hashes diferentes. Isso infla fila de extract, distorce rankings e polui digests.

**Objetivo:** camada de **entidade canônica** (`tool_key`) para agrupar itens sobre o mesmo produto antes do scoring público.

**Heurísticas V1 (sem ML):**

1. `canonical_url` normalizado (`github.com/org/repo`, sem trailing slash)
2. `tool_name` normalizado (lowercase, strip suffixes `-ai`, ` Inc`)
3. Match exato ou Jaro-Winkler > 0.92 com mesmo domínio
4. Opcional: `metadata_json.github_owner/repo` quando presente

**Comportamento:** segundo+ raw da mesma entidade → `status=skipped` + `metadata_json.duplicate_of` apontando para o raw “líder”; extract/score rodam no líder ou no mais recente.

## Tasks

- [x] Migration `0005_entity_resolution`: `tool_key`, `canonical_url` em `raw_items` + índices
- [x] Módulo `curation/entity.rs` + `curation/resolve.rs`
- [x] Hook pós-collect + reconcile no início do extract
- [x] `GET /reports/duplicates?limit=` — clusters com contagem por fonte
- [x] `claim_pending_batch`: pula pending quando líder já `extracted`
- [x] Testes unitários entity + build workspace
- [ ] Deploy cluster + migration `0005` + smoke duplicates API

## Validação

```bash
cargo test -p ai-radar-core entity
curl -fsS "$API/reports/duplicates?limit=10" | jq
# Após collect duplicado: pending não deve dobrar para mesma ferramenta
```

## Dependências

- **T-165** / pipeline extract ✅
- Facilita **T-235** (ranking limpo) e qualidade do digest **T-169**
