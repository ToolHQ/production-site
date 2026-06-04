# T-326 — agent-meter: Parent-Child Span Nesting

**Epic**: SaaS Revenue → Trace Visualization  
**Priority**: 🚨 Critical  
**Owner**: Copilot/VSCode  
**Est.**: 8h  
**Depende de**: T-325 (payload inspector confirma que ingest está correto)

---

## Contexto

Em Datadog/Jaeger, um "trace" tem spans aninhados: o LLM call é pai de sub-spans
(tool calls que o modelo decidiu executar). Atualmente o agent-meter exibe todos os
eventos flat, sem hierarquia — não é possível ver "quais tools foram invocadas durante
esse llm_chat específico".

O aninhamento correto exige:
1. `parent_call_id` no schema (FK para `agent_tool_calls.id`)  
2. Lógica no ingest para detectar pai (W3C traceparent ou heurística temporal)  
3. Renderização com indent + expand/collapse no waterfall

---

## Schema

```sql
ALTER TABLE agent_tool_calls
  ADD COLUMN IF NOT EXISTS span_id     TEXT,  -- W3C trace span ID (16 hex chars)
  ADD COLUMN IF NOT EXISTS parent_id   TEXT;  -- W3C parent span ID

CREATE INDEX IF NOT EXISTS idx_tool_calls_parent_id ON agent_tool_calls(parent_id)
  WHERE parent_id IS NOT NULL;
```

## Heurística de nesting (fallback sem W3C traceparent)

Para spans sem `parent_id` explícito, detectar pai por janela temporal:
- Um span A é pai de B se: `A.started_at <= B.started_at` AND `B.ended_at <= A.ended_at`
- Preferir o pai mais próximo (menor `ended_at - started_at`)
- Profundidade máxima: 5 níveis (evitar recursão infinita)

## API

- `TimelineEvent` adiciona `span_id: Option<String>`, `parent_id: Option<String>`, `depth: u8`
- A query de timeline já retorna `started_at`/`ended_at` — computar `depth` no Rust antes de serializar
- Serializar como lista flat com `depth` (frontend faz render com indent)

## Frontend (timeline.html)

```
▾ llm_chat · claude · 4.6s ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ├ read_file · 42ms ━━
  ├ grep_search · 180ms ━━━
  └ replace_string_in_file · 95ms ━━
▸ llm_chat · claude · 2.1s ━━━━━━━
  [collapsed — 3 children]
run_in_terminal · 1.2s ━━━━━━━━━
```

- `▾/▸` toggle expand/collapse por grupo
- Indent de 16px por nível de depth
- Cor do span pai usa opacidade 1.0, filhos 0.75
- Contagem de filhos no label quando colapsado
- Estado de collapse persistido em `sessionStorage`

## Acceptance Criteria

- [ ] Migration aplicada
- [ ] Ingest preenche `span_id`/`parent_id` quando `traceparent` header presente
- [ ] Heurística temporal funciona para traces sem W3C
- [ ] Waterfall renderiza indent por `depth`
- [ ] Toggle expand/collapse por grupo de filhos
- [ ] Zoom e minimap funcionam corretamente com nested view
- [ ] Agrupamento por tool/model ainda funciona (ignora hierarchy)
- [ ] Performance: 2000 eventos renderizados em <100ms

## Notas

- Para VS Code + GitHub Copilot: o VS Code envia `traceparent` via OTLP headers
  desde a versão 1.89+ — testar com conversas reais após deploy
- Heurística temporal é suficiente para Copilot que ainda não envia traceparent
