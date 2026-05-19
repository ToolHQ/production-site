# T-263: Agent Meter — UI Identity & Polish

- **Status**: In Progress
- **Priority**: 🔼 High
- **Owner**: Copilot/VSCode
- **Branch**: `feat/T-263-agent-meter-ui-identity`

## Context

O agent-meter possui estrutura funcional mas identidade visual fraca comparado ao
AI Radar (https://ai-radar.dnor.io). Análise lado a lado via browser headless mostra:

**AI Radar tem:**
- Ícone SVG animado (radar concêntrico, gradiente teal→sky→indigo) no favicon e header
- Topbar: brand (icon + title + subtitle "Decision Engine") + nav links
- Background glow sutil (gradient radial)
- Footer com links Health/Metrics
- Meta description, page title descritivo
- Tipografia hierárquica clara

**Agent Meter tem:**
- Texto simples sem ícone (nem favicon)
- Header minimalista sem brand identity
- Nenhum background texture
- Sem footer
- Page title genérico "agent-meter dashboard"
- Identidade visual fraca apesar de ter a paleta indigo/purple correta

O HTML é um único arquivo `include_str!` no binário Rust → toda mudança requer rebuild.

## Tasks

- [x] Criar branch `feat/T-263-agent-meter-ui-identity`
- [ ] Desenhar SVG icon gauge (32×32, paleta indigo, mesmo estilo do AI Radar)
- [ ] Embed favicon como data URI no `<link rel="icon">`
- [ ] Atualizar `<title>` e `<meta name="description">`
- [ ] Redesenhar header: brand (icon + "agent-meter" + subtitle) + health badge
- [ ] Adicionar `.bg-glow` CSS (radial gradient sutil indigo/purple no topo)
- [ ] Adicionar `<footer>` com links Health / Metrics
- [ ] Build + deploy + validar no browser
- [ ] PR e merge
