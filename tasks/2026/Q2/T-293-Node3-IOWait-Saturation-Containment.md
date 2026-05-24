# T-293: Cluster Pulse — Node-3 I/O Wait Saturation Containment (ClickHouse/Prometheus)

- **Status**: Backlog
- **Priority**: 🚨 Critical
- **Owner**: Copilot/VSCode
- **Epic**: Infra / Observability
- **Est**: 4h

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
