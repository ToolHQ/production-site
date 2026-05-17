# T-245: AI Radar — Compare Deep-Link & Category UX

- **Status**: Backlog
- **Priority**: 🔽 Low
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 2h

## Context

O Comparator (**T-237**) existe em `#/compare`, mas o fluxo Explorer → Compare exige copiar categoria manualmente.

## Tasks

- [ ] Hash/query: `#/compare?category=observability` pré-preenche formulário
- [ ] Botão no detalhe do item (**T-242**) e na lista (ação rápida)
- [ ] Autocomplete de categorias já vistas (distinct do último `GET /items?limit=500` ou endpoint leve)
- [ ] Documentar no README do ai-radar

## Dependências

- **T-237** ✅ compare UI
- **T-242** (opcional, link no detalhe)

## Validação

- Clicar “Comparar” em item `category=agents` → POST compare com mesma categoria
