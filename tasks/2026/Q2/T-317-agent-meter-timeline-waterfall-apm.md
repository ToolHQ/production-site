# T-317: agent-meter — Timeline Waterfall APM

## Objetivo
Substituir a flat-list atual da página `/conversations/:id` por uma visualização **waterfall estilo Jaeger/Tempo/Datadog APM**, com barras horizontais proporcionais à duração de cada evento posicionadas na linha do tempo absoluta.

## Por que (produto / monetização)
A flat-list atual mata a usabilidade em conversas reais (1500+ eventos). Waterfall é a vista padrão que **todo APM moderno** entrega — sem isso, o produto parece um log viewer, não APM. Esta é **a feature visível mais alta de ROI** para fechar venda demonstrando paridade com Helicone/LangSmith/Datadog.

## Especificações

### 1. Layout
- Eixo X: tempo absoluto (`started_at` → `ended_at` da conversa)
- Eixo Y: 1 linha por evento, ordenado por `started_at`
- Barra: largura ∝ `duration_ms`, posicionada no offset relativo ao início
- Régua de tempo no topo (5 ticks: 0s, 25%, 50%, 75%, 100%)
- Cores: `llm_chat` (accent), tools (cinza), erros (vermelho), MCP wrapper (cyan)

### 2. Interação
- **Hover na barra** → tooltip flutuante: tool, model, mcp_server, duração, tokens in/out, custo USD
- **Click na barra** → drawer lateral com payload completo do evento (prompt parseado, response, error stack)
- **Zoom**: scroll-wheel altera escala temporal; arraste pan horizontal
- **Filtros do sidebar** preservados: filterModel, filterTool (novo), filterErrorOnly (novo)
- **Mini-mapa** no topo (overview de toda timeline, área visível destacada)

### 3. Agrupamento
- Toggle "Group by tool" colapsa eventos consecutivos da mesma tool
- Banda separada para `llm_chat` (model calls) vs tools (file/git/mcp)

### 4. Performance
- Virtualização: render apenas o que está no viewport (canvas ou SVG segmentado)
- Suportar 5000+ eventos sem lag (target: 60fps em conversa de 1519 eventos)

## Implementação

### Frontend (`apps/agent-meter/crates/collector/ui/timeline.html`)
- Substituir bloco `event-item` por `<canvas>` (preferido p/ 5k eventos) ou SVG com `transform`
- Helper `computeLayout(events, viewportStart, viewportEnd)` calcula `(x, width)` por evento
- Drawer reutiliza `--bg-elevated` / mesmo design system do dashboard

### Backend (já existe)
- `/conversations/:id/timeline` já retorna `started_at`, `ended_at`, `duration_ms` por evento — sem mudanças necessárias
- Adicionar `cost_usd` por evento (depende de **T-318**)

## Critérios de Aceitação
- [ ] Conversa de 1519 eventos renderiza < 1s e roda em 60fps no scroll
- [ ] Tooltip aparece em < 50ms após hover
- [ ] Drawer com payload abre sem reload
- [ ] Mini-mapa funcional com viewport draggable
- [ ] **Browser MCP**: zero `[error]` no console, screenshot capturado, fluxo dashboard → conversa → drawer testado

## Estimativas
- Layout/canvas: 3h
- Tooltip + drawer: 1h
- Mini-mapa + zoom: 2h
- **Total**: ~6h (revisado de 4h)

## Owner
**Copilot/VSCode**

## Status
- [ ] Layout waterfall implementado
- [ ] Tooltip + drawer implementado
- [ ] Mini-mapa + zoom implementado
- [ ] Validação browser via MCP

## Dependências
- Bloqueia: T-318 (custo USD por evento aparece no tooltip/drawer)
- Bloqueia: T-323 (benchmark público usa essa view como showcase)
