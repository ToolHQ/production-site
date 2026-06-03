# T-318: agent-meter — Cost Attribution Engine (FinOps)

## Objetivo
Calcular **custo em USD** por evento, conversa, projeto e organização, usando uma tabela versionada de preços por modelo. Esse é **o pilar FinOps** que diferencia o produto de log viewers.

## Por que (produto / monetização)
- Sem custo em USD não há **história FinOps** — e FinOps é o ângulo de venda mais quente em times de AI (CFOs querendo controlar gasto com OpenAI/Anthropic).
- "Você gastou $1.847 em llm_chat este mês com Cursor, 73% em claude-3-5-sonnet" é a frase que vende.
- Habilita T-320 (budget alerts) e tier de pricing baseado em $ ingerido.

## Especificações

### 1. Tabela de preços (`model_pricing`)
```sql
CREATE TABLE model_pricing (
  id SERIAL PRIMARY KEY,
  model VARCHAR(128) NOT NULL,            -- "claude-3-5-sonnet-20241022"
  vendor VARCHAR(64) NOT NULL,            -- "anthropic"
  input_per_million_usd NUMERIC(10,4),    -- 3.00
  output_per_million_usd NUMERIC(10,4),   -- 15.00
  cached_input_per_million_usd NUMERIC(10,4) NULL,  -- 0.30
  effective_from TIMESTAMPTZ NOT NULL,
  effective_to TIMESTAMPTZ NULL,
  source_url TEXT,
  UNIQUE(model, effective_from)
);
```

Seed inicial: GPT-4o, GPT-4o-mini, Claude 3.5/3.7 Sonnet, Claude 3.5 Haiku, Gemini 1.5/2.0 Pro/Flash, o3-mini, DeepSeek-V3.

### 2. Cálculo
- View materializada `event_cost`:
  ```sql
  cost_usd = (tokens_in - cached) * input/1M + cached * cached_input/1M + tokens_out * output/1M
  ```
- Refresh a cada 5min (CronJob).
- Para evento sem match de model: `cost_usd = NULL`, flag `pricing_missing=true`.

### 3. Endpoints
- `GET /api/cost/summary?from=&to=&group_by=model|tool|conversation|day` → totais
- `GET /api/cost/budget` → orçamento atual e burn rate
- `GET /conversations/:id/timeline` → adicionar campo `cost_usd` por evento e `total_cost_usd` no header

### 4. UI
- KPI card no dashboard: `Cost Today` / `Cost MTD` / `Top Model by Cost` / `Burn Rate`
- Sparkline `Cost Over Time` (já existe `calls-over-time`, espelhar)
- Tooltip do waterfall (T-317) mostra USD
- Página `/cost` com breakdown: por modelo (donut), por tool (bar), por dia (line), top 10 conversas mais caras

### 5. CLI e admin
- `agent-meter pricing seed` — popula a tabela do seed JSON em `crates/collector/data/pricing.json`
- `agent-meter pricing diff` — compara live vs JSON e reporta drift

## Critérios de Aceitação
- [ ] `model_pricing` populada com ≥ 20 modelos comuns
- [ ] `cost_usd` aparece em `event_cost` para ≥ 95% dos eventos `llm_chat` reais
- [ ] KPI cards atualizam em tempo real
- [ ] Página `/cost` renderiza com dados reais
- [ ] **Browser MCP** validado

## Estimativas
- Schema + seed: 1h
- View materializada + jobs: 2h
- API endpoints: 2h
- UI dashboard + página `/cost`: 3h
- **Total**: ~8h

## Owner
**Copilot/VSCode**

## Dependências
- Habilita: T-317 (custo no tooltip), T-320 (budget alerts), T-321 (Stripe usage-based)
