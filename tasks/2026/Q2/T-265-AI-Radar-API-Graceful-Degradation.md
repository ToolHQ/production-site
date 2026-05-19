# T-265: AI Radar — API Graceful Degradation

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

Rotas além de `/metrics` podem falhar hard quando DB oscila. Operador perde console inteiro.

## Tasks

- [ ] Padrão: rotas read-only retornam 503 estruturado + retry-after quando pool esgotado
- [ ] `/stats` degradado: omitir bloco embeddings se query falhar (não 500)
- [ ] Timeout explícito em queries pesadas do Explorer
- [ ] Testes de contrato 503

## Definition of Done

- Console home carrega mesmo com embedding stats indisponível

## Dependências

T-263, T-264
