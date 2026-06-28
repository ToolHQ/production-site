# T-361: agent-meter — Database Performance Indexes

## Objetivo

Otimizar queries analíticas do agent-meter que estão lentas (>1s) devido à falta de índices compostos.

## Problema Identificado

### Queries Lentas Detectadas

1. **Task leaderboard por conversation** (~1.5s)
```sql
SELECT conversation_id AS task_id, 
       COUNT(*)::bigint AS tool_calls,
       SUM(estimated_total_tokens)::bigint AS total_estimated_tokens,
       SUM(duration_ms)::bigint AS total_duration_ms,
       COUNT(*) FILTER (WHERE NOT ok)::bigint AS errors,
       COUNT(DISTINCT tool_name)::bigint AS distinct_tools
FROM agent_tool_calls
WHERE conversation_id IS NOT NULL
GROUP BY conversation_id
ORDER BY tool_calls DESC
LIMIT 100;
```

2. **Eventos feed** (~3s)
```sql
SELECT event_id, tool_name, model, started_at, duration_ms, ok, ...
FROM agent_tool_calls
WHERE (started_at >= $1) AND (started_at <= $2)
ORDER BY started_at DESC, event_id DESC
LIMIT 100;
```

### Análise do Plano de Execução

- **Problema**: Seq Scan em 23k linhas + Sort + GroupAggregate
- **Custo**: ~5960 (sem índice) vs ~500 (com índice ideal)
- **Índices existentes**: 
  - `idx_agent_tool_calls_conversation` (conversation_id)
  - `idx_atc_events_feed` (started_at DESC, event_id DESC)

## Índices a Criar

### Índice 1: conversation_id + started_at DESC

**Justificativa**: A query de tasks agrupa por `conversation_id` e filtra por `conversation_id IS NOT NULL`. O índice composto acelera o GROUP BY.

```sql
CREATE INDEX CONCURRENTLY idx_atc_conversation_stats 
ON agent_tool_calls (conversation_id, started_at DESC, tool_name)
WHERE conversation_id IS NOT NULL;
```

### Índice 2: started_at DESC para eventos feed

**Justificativa**: Queries de eventos usam `ORDER BY started_at DESC, event_id DESC`. Já existe `idx_atc_events_feed`, mas vamos verificar se é suficiente.

```sql
-- Verificar se idx_atc_events_feed já existe e é usado
-- Se não for suficiente, criar:
CREATE INDEX CONCURRENTLY idx_atc_started_event 
ON agent_tool_calls (started_at DESC, event_id DESC);
```

### Índice 3: usd_cost para queries de custo

**Justificativa**: Queries de custo agregam por `usd_cost`. Já existe `idx_atc_usd_cost` mas vamos verificar.

```sql
-- Verificar se idx_atc_usd_cost cobre as queries de cost
-- Se não for suficiente, criar:
CREATE INDEX CONCURRENTLY idx_atc_cost_aggregation 
ON agent_tool_calls (started_at DESC, usd_cost, model)
WHERE usd_cost IS NOT NULL;
```

## Plano de Execução

1. **Verificar índices existentes** (não recriar duplicados)
2. **Criar índices com CONCURRENTLY** (não bloqueia writes)
3. **Testar queries** com EXPLAIN ANALYZE
4. **Validar performance** antes/depois
5. **Abrir PR** com migration SQL
6. **Merge para main**

## Critérios de Sucesso

- [x] Queries de tasks leaderboard < 500ms (atingido: 44ms)
- [x] Queries de eventos feed < 500ms (atingido: 2.7ms)
- [x] Queries de cost summary < 500ms (já tinha índice)
- [x] Zero locks em produção durante criação dos índices (usado CONCURRENTLY)

## Resultados Obtidos

### Antes
```
Execution Time: 354.999ms
```

### Depois
```
Execution Time: 44.553ms
```

**Melhoria: 8x mais rápido** (354ms → 44ms)

## Arquivos Criados

- `docs/tasks/T-361-agent-meter-db-perf-indexes.md` - Documentação da task
- `apps/agent-meter/migrations/20260628000001_agent_meter_perf_indexes.sql` - Migration SQL

## Referências

- Logs de alerta: `slow statement: execution time exceeded alert threshold`
- Tabela: `agent_tool_calls` (23.338 registros)
- Threshold atual: 1s (alerta), objetivo: <500ms