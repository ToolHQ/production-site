# T-355: agent-meter — Cost engine: compute_event_usd performance

- **Status**: To Do
- **Priority**: 🔼 High
- **Owner**: Copilot/VSCode
- **Estimate**: 2h

## Context

`compute_event_usd()` é uma função PL/pgSQL marcada IMMUTABLE que faz 2 SELECTs internos
na tabela `model_pricing` para cada row. É chamada inline em TODAS as queries de custo
(cost_summary KPIs, by_model, by_day, list_conversations, timeline).

Com 14K+ rows isso ainda é aceitável, mas vai degradar com crescimento.
A heurística de estimativa de tokens (request_bytes/4) também é muito simplista.

## Tasks

- [ ] Benchmark: `EXPLAIN ANALYZE` nas queries de custo com tabela atual (14K rows)
- [ ] Opção 1: Pré-calcular `usd_cost` na inserção (coluna `usd_cost numeric` + trigger)
- [ ] Opção 2: Materialized view `cost_daily_mv` com refresh periódico
- [ ] Melhorar heurística de token estimation: usar ratio por modelo (LLMs têm ~3.5 chars/token, não 4 bytes)
- [ ] Considerar cached_tokens no cálculo (atualmente proxy não envia cached_tokens na request)
- [ ] Testes: comparar custo calculado vs custo real de API bills
