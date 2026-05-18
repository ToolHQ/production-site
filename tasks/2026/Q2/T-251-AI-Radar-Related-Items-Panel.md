# T-251: AI Radar — Related Items Panel

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

No detalhe do item (**T-242**), mostrar “ferramentas relacionadas” por vizinhança vetorial (mesma categoria opcional).

## Tasks

- [ ] `GET /items/:id/related?limit=5` — top-k cosine excluindo self
- [ ] UI: seção abaixo do painel de sinais, links para `#/items/:id`
- [ ] Ocultar seção quando sem embedding do item

## Dependências

- **T-248** ✅ embeddings persistidos
- **T-242** ✅ item detail shell

## Validação

- Item com embedding → ≥1 related com similarity > threshold
