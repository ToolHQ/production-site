# T-265: AI Radar — API Graceful Degradation

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

Rotas além de `/metrics` podem falhar hard quando DB oscila. Operador perde console inteiro.

## Tasks

- [x] Padrão: rotas read-only retornam 503 estruturado + `Retry-After` em falhas transitórias
- [x] `/stats` degradado: omitir bloco embeddings se query falhar (não 500)
- [x] Timeout explícito em queries pesadas do Explorer (8s) e `/stats` (5s)
- [x] Testes de contrato 503 (`error.rs`, `RepoError::is_transient`)

## Definition of Done

- Console home carrega mesmo com embedding stats indisponível

## Dependências

T-263, T-264
