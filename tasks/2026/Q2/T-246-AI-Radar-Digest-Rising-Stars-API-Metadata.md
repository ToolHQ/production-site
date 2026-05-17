# T-246: AI Radar — Digest Rising Stars API Metadata

- **Status**: Done
- **Priority**: 🔽 Low
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

**T-241** enriquece o Markdown do digest. Esta task fecha o loop **API + console**: `metadata_json` estruturado para renderizar cards/charts sem re-parse do Markdown.

## Tasks

- [ ] Schema estável em `metadata_json`: `rising_stars[]`, `trending_adoption[]`, `sources_alert[]`
- [ ] `GET /digests/:id` expõe blocos; viewer `#/digests/:id` mostra seção “Destaques” acima do Markdown
- [ ] Pipeline stats strip na home: consumir `GET /stats` (pending raw, extracted, scored)
- [ ] Alinhar com `generator: digest-v2`

## Dependências

- **T-241** (mesmo sprint; pode implementar em paralelo após contrato de metadata)

## Validação

- Digest novo com metadata → console mostra cards sem depender só de `marked`
