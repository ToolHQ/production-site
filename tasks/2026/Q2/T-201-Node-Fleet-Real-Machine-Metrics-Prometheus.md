# T-201 — Node Fleet: Real Machine Metrics via Prometheus node_exporter

**Status**: Backlog  
**Owner**: Copilot/VSCode  
**Priority**: 🔼 High  
**Epic**: Cluster Pulse / Observability  
**Est.**: 4h

---

## Problema

O Node Fleet atual (T-199) exibe dados de **alocação Kubernetes** (`status.allocatable`), que são valores **fixos e idênticos** para todos os nós:

```
k8s-master   800m   5.2 GiB   43.4 GiB   — 
k8s-node-1   800m   5.2 GiB   43.4 GiB   💾 DiskPressure
k8s-node-2   800m   5.2 GiB   43.4 GiB   —
k8s-node-3   800m   5.2 GiB   43.4 GiB   —
```

Isso não serve para triage. O operador quer saber:

- **Qual nó está com CPU alta agora?**
- **Qual nó tem menos memória livre?**
- **O disco de node-1 está a 85%?**
- **Isso está piorando ou estabilizando?** (trend)

---

## Objetivo

Substituir dados `status.allocatable` por **métricas reais de máquina** vindas do Prometheus (node_exporter), com:

- Valor **percentual** (% uso) + valor **absoluto** (GiB usado / total)
- **Série temporal** (últimos 30 min, pontos a cada 5 min) para sparkline de tendência
- Coluna de **Disco real** (`/` filesystem) ao invés do ephemeral K8s

---

## Investigação Prévia

### Prometheus já disponível

O endpoint `/api/live/overview` já consulta o Coroot Prometheus em `coroot-prometheus-server.coroot.svc.cluster.local:9090`. O código Rust em `src/main.rs` já tem `fetch_prometheus()` e structs de série temporal.

### Métricas node_exporter

Verificar disponibilidade das seguintes métricas no Prometheus do cluster:

```promql
# CPU % por nó (média 5 min)
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memória % usada
100 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100)

# Memória absoluta: usada e total
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes  # usado
node_memory_MemTotal_bytes                                   # total

# Disco % usado (rootfs /)
100 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100)

# Disco absoluto
node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_avail_bytes{mountpoint="/"}
node_filesystem_size_bytes{mountpoint="/"}
```

### Mapeamento instância → nó K8s

O label `instance` no node_exporter vem no formato `10.0.1.100:9100` (IP interno). Precisamos mapear para `k8s-master`, `k8s-node-1` etc. via `kubectl get nodes -o wide` (já disponível no código).

---

## Escopo de Implementação

### Backend Rust (`src/main.rs`)

- [ ] **Investigar**: confirmar quais métricas node_exporter estão ativas no Prometheus do cluster
  - Query de validação: `curl -sk 'http://coroot-prometheus-server...:9090/api/v1/label/job/values'`
  - Verificar se label `job="node-exporter"` ou similar existe
- [ ] Criar struct `NodeMetrics` com campos:
  ```rust
  pub struct NodeMetrics {
      pub cpu_percent: f64,
      pub mem_used_bytes: u64,
      pub mem_total_bytes: u64,
      pub mem_percent: f64,
      pub disk_used_bytes: u64,
      pub disk_total_bytes: u64,
      pub disk_percent: f64,
      pub cpu_series: Vec<TimeSeries>,   // 30 min, 5 min steps
      pub mem_series: Vec<TimeSeries>,
      pub disk_series: Vec<TimeSeries>,
  }
  ```
- [ ] Adicionar `node_metrics: HashMap<String, NodeMetrics>` ao `LiveOverview` (chave = hostname)
- [ ] Implementar `fetch_node_metrics()` que faz query Prometheus range + instant
- [ ] Mapeamento IP→hostname via `nodes.items` já disponível em `build_live_overview()`
- [ ] Fallback gracioso: se node_exporter não estiver disponível, retornar campos `null` (não quebrar)

### Frontend (`NodesPanel.tsx`)

- [ ] Adicionar colunas: **CPU %**, **Mem %**, **Disk %** com valor absoluto como tooltip/secondary
- [ ] Minibar de progresso visual (CSS puro) por célula: `[████░░░░] 52%`
- [ ] Sparkline de tendência (SVG inline simples, sem lib) se série temporal disponível
- [ ] Manter coluna `Alerts` (DiskPressure, MemPressure do K8s) separada dos dados Prometheus

### Layout proposto

```
| Node       | Role          | CPU          | Memory       | Disk (/)     | Alerts |
|------------|---------------|--------------|--------------|--------------|--------|
| k8s-master | control-plane | 45% 1.8c     | 62% 3.2/5.2G | 78% 38/49G   | —      |
| k8s-node-1 | worker        | 89% 3.6c ↑   | 58% 3.0/5.2G | 85% 42/49G   | 💾     |
```

---

## Riscos e Mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| node_exporter não disponível | Alto | Fallback para dados K8s allocatable + flag `source: "k8s-only"` |
| IP→hostname mismatch | Médio | Usar label `kubernetes_node` do Prometheus se disponível, senão mapear por IP |
| Rust build 15 min + disco k8s-node-1 | Alto | BuildKit prune automático pós-build (T-196) já em vigor |
| Séries temporais aumentam payload | Baixo | Limitar a 6 pontos × 3 métricas × 4 nós = 72 floats |

---

## Definition of Done

- [ ] `GET /api/live/overview` retorna `node_metrics` com CPU%, mem%, disk% reais por nó
- [ ] Percentuais visíveis no Node Fleet com valores absolutos (ex: `62% · 3.2/5.2 GiB`)
- [ ] Trend de 30 min visível (sparkline ou indicador ↑/↓/→)
- [ ] Nenhuma regressão nos dados existentes (T-199 DiskPressure/MemPressure badge)
- [ ] Deploy em `reports.dnor.io` — validado via `curl /api/live/overview | jq '.node_metrics'`
