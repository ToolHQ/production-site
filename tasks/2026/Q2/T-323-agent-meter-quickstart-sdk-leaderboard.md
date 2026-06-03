# T-323: agent-meter — Quickstart Docs + SDK + Public Benchmark

## Objetivo
Reduzir time-to-first-event para **< 60 segundos** em qualquer agente (Cursor, Copilot, Claude Code, custom Python/TS), via docs canônicas + SDK leve. Bonus: leaderboard público "Top Agents by Cost/Latency" como motor de aquisição.

## Por que (produto / monetização)
- Time-to-value é o KPI #1 de PLG (product-led growth) SaaS. Se demorar > 5min, 80% desiste.
- SDK simples (`pip install agent-meter` / `npm i agent-meter`) reduz fricção de OTLP cru.
- Leaderboard público vira marketing orgânico: dev tweeta "look, my agent is in the top 10 fastest".

## Especificações

### 1. Quickstart canônico (docs/quickstart)
- 4 abas: **Cursor** | **Copilot/VSCode** | **Claude Code** | **OTLP genérico**
- Cada uma:
  - Copy-paste 1 comando de `curl` ou snippet
  - Screenshot do resultado em < 10s
  - Vídeo Loom de 60s

### 2. SDK Python (`pip install agent-meter`)
```python
from agent_meter import meter

meter.init(api_key="amk_live_...")

with meter.span(tool="my_tool", model="gpt-4o") as span:
    # ... do work
    span.tokens(input=100, output=200)
```
- Wrapper sobre OTLP exporter, but with sane defaults
- Auto-detect env: `AGENT_METER_API_KEY`
- Buffered HTTP client, batch every 5s
- Repo: `apps/agent-meter/sdk-python/`

### 3. SDK TypeScript (`npm i @agent-meter/sdk`)
```ts
import { meter } from '@agent-meter/sdk';
meter.init({ apiKey: process.env.AGENT_METER_API_KEY });
await meter.span({ tool: 'read_file', model: 'claude-3-5-sonnet' }, async (span) => {
  // ... do work
  span.tokens({ input: 100, output: 200 });
});
```
- Pure ESM, zero deps (use `fetch`)
- Repo: `apps/agent-meter/sdk-ts/`

### 4. Cursor / Copilot / Claude Code wrappers
- Já existe `mcp-wrapper`. Documentar bem em `docs/quickstart-cursor.md` etc
- 1 comando por IDE: `curl -fsSL https://agent-meter.com/install/cursor | bash`

### 5. Public Benchmark / Leaderboard
- Página `/leaderboard` no site público (T-321)
- Opt-in (settings checkbox "Share anonymized stats with public leaderboard")
- Métricas:
  - Top 10 fastest agents (median p50 by tool)
  - Top 10 cheapest per task (cost/conversation)
  - Distribution chart of cost-per-conversation across all opted-in users
- Anonimizado: só `agent_kind` (cursor/copilot/etc) + `model` + métricas — nada identificável
- Atualizado nightly via CronJob

### 6. Comparação com competitors (página `/vs`)
- Tabela honesta: agent-meter vs Helicone vs Langfuse vs LangSmith
- Highlights: zero-code OTLP, FinOps focus, open core
- Atualizada quando competidores mudam preço

## Critérios de Aceitação
- [ ] Quickstart documentado em 4 IDEs com screenshots
- [ ] SDK Python publicado no PyPI (`agent-meter`)
- [ ] SDK TS publicado no npm (`@agent-meter/sdk`)
- [ ] Time-to-first-event < 60s (cronometrado em vídeo)
- [ ] Leaderboard live e atualizando nightly
- [ ] **Browser MCP**: navegar quickstart Cursor → executar snippet → ver evento no dashboard

## Estimativas
- Docs quickstart (4 IDEs + screenshots/loom): 3h
- SDK Python + publicação: 3h
- SDK TS + publicação: 2h
- Leaderboard backend + UI: 4h
- Página `/vs`: 2h
- **Total**: ~14h (2 dias)

## Owner
**Copilot/VSCode**

## Dependências
- Requer: T-319 (API keys), T-321 (site público)
- Habilita: aquisição orgânica, redução de CAC
