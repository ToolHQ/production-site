# T-252: AI Radar — Semantic Duplicate Clusters Report

- **Status**: Done
- **Priority**: 🔽 Low
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 6h

## Context

**T-231** dedup por `tool_key`/URL. Clusters semânticos pegam o mesmo produto com nomes diferentes ou resumos parecidos (cosine ≥ threshold, ex. 0.92).

## Tasks

- [ ] `GET /reports/semantic-duplicates?threshold=&limit=` — pares/clusters
- [ ] Console `#/reports/semantic-duplicates` (nav Relatórios)
- [ ] Não auto-skip no pipeline (só relatório operador) — evitar falsos positivos
- [ ] Documentar threshold e limites no README

## Dependências

- **T-248** ✅
- **T-243** ✅ padrão de relatórios no console

## Validação

- `curl /reports/semantic-duplicates?limit=10` após batch embed
