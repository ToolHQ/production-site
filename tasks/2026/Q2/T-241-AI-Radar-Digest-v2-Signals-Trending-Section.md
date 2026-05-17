# T-241: AI Radar — Digest v2 Signals & Trending Section

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 6h

## Context

A **Fase 17** entregou sinais no pipeline (`adoption`, `velocity_tier`, `source_health`, `feedback_calibration`) mas o digest (**T-169**) ainda lista só decisões e regras clássicas. Operadores não veem **tendências** nem alertas de fonte ruidosa no artefato semanal.

**Objetivo:** enriquecer `pipeline/digest.rs` e o Markdown renderizado com seções acionáveis:

| Seção | Fonte |
| ----- | ----- |
| **Em ascensão** | Top N `velocity_spike` / `velocity_tier=hot` (últimos 7d) |
| **Adoção** | Destaques `adoption.tier` ≥ community |
| **Fontes** | Resumo `GET /sources/health` — aviso se `noisy`/`degraded` |
| **Calibração** | Contagem de itens com `feedback_calibration` aplicado no período |

**Arquivos:** [`digest.rs`](../../../apps/ai-radar/crates/ai-radar-core/src/pipeline/digest.rs), [`app.js`](../../../apps/ai-radar/crates/ai-radar-api/assets/app.js) (labels PT alinhados).

## Tasks

- [ ] Query agregada: top velocity + adoption no período do digest
- [ ] `render_markdown`: seções `## Em ascensão`, `## Fontes (saúde)`, nota de calibração
- [ ] `metadata_json`: `signals_summary`, `rising_tool_keys[]`, `noisy_source_ids[]` (base para **T-246** / console)
- [ ] `generator`: `digest-v2` (manter compat com digests antigos)
- [ ] Testes unitários em `digest.rs` (fixtures mínimas)

## Dependências

- **T-234** ✅ velocity
- **T-233** ✅ adoption
- **T-238** ✅ source health

## Validação

- `cargo test -p ai-radar-core digest`
- `POST /digest/run` + conferir Markdown em `https://ai-radar.dnor.io/#/digests`
