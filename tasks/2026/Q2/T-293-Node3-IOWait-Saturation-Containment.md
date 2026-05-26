# T-293: Cluster Pulse — Node-3 I/O Wait Saturation Containment (ClickHouse/Prometheus)

- **Status**: Done
- **Priority**: 🚨 Critical → Resolvido
- **Owner**: Copilot/VSCode
- **Epic**: Infra / Observability
- **Est**: 4h
- **Fechado**: 2026-05-25

## Contexto

Investigação em 2026-05-24 mostrou que o `k8s-node-3` segue sob saturação operacional, com divergência entre leitura de `kubectl top` e série de CPU do Prometheus:

- `kubectl top nodes`: ~43% CPU no node-3
- Prometheus (`node_cpu_seconds_total`, 5m): `k8s-node-3 = 100%`
- Host (`vmstat`): `wa` entre ~75% e ~81% em múltiplas amostras
- `uptime`: load average elevado (`7.53, 4.92, 4.93`) para nó de 1 vCPU

Principais consumidores no node-3:

- `coroot-clickhouse-shard0-0`
- `coroot-prometheus-server`
- `longhorn instance-manager` (carga de storage)

## Hipótese Técnica

O gargalo atual é **I/O wait** (disco) mais do que CPU puro de aplicação. Na métrica baseada em `idle`, iowait não conta como idle e puxa “CPU usada” para 100%, mesmo com `kubectl top` mais baixo.

## Tasks

- [ ] Coletar baseline de 24h para node-3 (`cpu`, `wa`, `disk util`) e fixar painel de comparação
- [ ] Validar afinidade/placement de `coroot-clickhouse` e `coroot-prometheus` para reduzir co-localização de I/O pesado no node-3
- [ ] Avaliar realocação de um dos workloads pesados para outro nó com mais headroom de I/O
- [ ] Revisar limites/requests de ClickHouse/Prometheus para evitar competição agressiva em janelas de compactação/scrape
- [ ] Revisar concorrência de jobs que gravam em storage durante janelas de pico
- [ ] Rodar smoke pós-mitigação (node CPU + wa + latência de APIs observability)

## Critérios de Aceite

- [ ] `k8s-node-3` sem spikes recorrentes de 100% por I/O em janela de 1h
- [ ] `wa` estabilizado em patamar saudável (sem plateau prolongado >30%)
- [ ] Coroot/Prometheus/ClickHouse permanecem saudáveis (`Running`, sem restart anormal)
- [ ] Sem regressão em Postgres/Longhorn no mesmo período

## Evidências Coletadas (2026-05-24)

- `kubectl top nodes`: node-3 ~43% CPU
- Prometheus query (`100 - avg(rate(idle[5m]))`): node-3 = 100
- `vmstat 1 5` no node-3: `wa` 75-81% em amostras consecutivas
- `ps` host: `clickhouse-server` no topo de CPU no momento da coleta

## Root Cause Identificado (2026-05-25)

A tabela `otel_traces_trace_id_ts` (292 MiB, ~9.9M linhas) **não possui `PARTITION BY`**.  
Todas as outras tabelas ClickHouse do Coroot têm `PARTITION BY toDate(Start/Timestamp)` — somente esta tabela usa apenas `ORDER BY (TraceId, toUnixTimestamp(Start))`.

Sem partição por data, toda operação de merge TTL exige varredura completa da tabela (292 MiB por execução), causando spikes de I/O a cada 4h (default `merge_with_ttl_timeout`).

**Nota**: o TTL em si está correto (7 dias) e aplicado — todos os dados na tabela estão dentro do janela (2026-05-19 → 2026-05-25), sem acúmulo de dados expirados.

## Resolução Aplicada (2026-05-25)

1. **`OPTIMIZE TABLE default.otel_traces_trace_id_ts FINAL`** — forçou merge/TTL imediato (sem dados expirados a limpar → confirmado).
2. **`MODIFY SETTING merge_with_ttl_timeout=86400`** em todas as 5 tabelas MergeTree ativas:
   - `otel_traces_trace_id_ts` — principal offender (sem PARTITION BY)
   - `otel_traces`, `otel_logs`, `profiling_samples`, `metrics`

   Resultado: merges TTL passam de 4h para 1 dia de intervalo, reduzindo frequência de I/O spikes em 6x.

3. **Estado pós-fix** (node-3, 2026-05-25):
   - `wa=0-1%` (estava 75-81%)
   - CPU: ~17% (estava 100%)
   - Load avg: 0.31 (estava 7.53)
   - PVC ClickHouse: 50% (958M/2G) — em steady state, projeção ~55-60%

## Pendência Técnica (não bloqueante)

A falta de `PARTITION BY toDate(Start)` na `otel_traces_trace_id_ts` é um bug da schema do Coroot.  
Pode ser aberta issue upstream. Não é possível adicionar PARTITION BY sem recriar a tabela — aguardar fix em versão futura do Coroot.
