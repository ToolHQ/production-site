# T-199: Cluster Pulse — Node Metrics Panel (CPU/mem/disk por nó)

- **Status**: Backlog
- **Priority**: 🔽 Medium
- **Epic/Owner**: Observability / DevExp / **Copilot/VSCode**
- **Estimation**: 3h
- **Opened**: 2026-05-16

## Context

O Cluster Pulse (`rs-observability-api` + `web-v2`) expõe métricas cluster-level (CPU%, memory%, restart events), mas **não exibe breakdowns por nó**.
Com 4 nós ARM64 (k8s-master + k8s-node-1/2/3), a falta de visibilidade por nó dificulta triagem de incidentes de DiskPressure e CPU starvation (ex: T-193, T-102).

### Gap atual no `/api/live/overview`

```rust
// NodeResource em main.rs — apenas conditions (Ready, DiskPressure, ...)
struct NodeResource {
    metadata: ResourceMetadata,
    status: NodeStatus,
}
struct NodeStatus {
    conditions: Vec<NodeCondition>,
    // ❌ sem: allocatable, capacity, ephemeral-storage
}
```

No frontend (`api.ts`):
```typescript
// LiveSummary — apenas totais
nodes_ready: number;
nodes_total: number;
// ❌ sem: NodeStat por nó
```

## Tasks

### Backend (Rust — `apps/rs-observability-api/src/main.rs`)

- [ ] Adicionar campo `allocatable` e `capacity` ao `NodeStatus`:
  ```rust
  struct NodeStatus {
      conditions: Vec<NodeCondition>,
      allocatable: Option<NodeAllocatable>,  // cpu (string), memory (string), ephemeral_storage (string)
      capacity: Option<NodeAllocatable>,
  }
  ```
- [ ] Criar struct `NodeStat` para emissão no `LiveOverview`:
  ```rust
  struct NodeStat {
      name: String,
      role: String,          // "control-plane" | "worker"
      ready: bool,
      disk_pressure: bool,
      memory_pressure: bool,
      cpu_allocatable_millicores: u64,
      memory_allocatable_bytes: u64,
      ephemeral_storage_bytes: u64,
      pod_count: u32,
  }
  ```
- [ ] Parsear CPU (ex: "940m" → millicores) e memória (ex: "5593Mi" → bytes)
- [ ] Incluir `nodes: Vec<NodeStat>` no struct `LiveOverview` retornado pelo endpoint `/api/live/overview`
- [ ] Queries Prometheus por nó (via label `node=`):
  - `node_resources_cpu_usage_seconds_total{node="k8s-master"}` — CPU% por nó
  - `node_resources_memory_available_bytes{node="k8s-master"}` — memoria livre por nó
  - `node_filesystem_avail_bytes{mountpoint="/", node="k8s-master"}` — disco por nó

### Frontend (TypeScript — `apps/rs-observability-api/web-v2/src/`)

- [ ] Adicionar `NodeStat` e `nodes: NodeStat[]` ao `LiveOverview` em `types/api.ts`
- [ ] Criar `components/NodesPanel.tsx`:
  - Tabela/grid de nós com: nome, role badge, status (Ready/NotReady), DiskPressure, MemoryPressure
  - Barra de CPU% (calculada: `pod_cpu_used / cpu_allocatable`)
  - Barra de Memory% (calculada: se Prometheus disponível)
  - Indicador de disco (DiskPressure = 🔴, else 🟢)
  - Estética consistente com `SummaryGrid.tsx` e `ServiceCard.tsx`
- [ ] Integrar `NodesPanel` no `app.tsx` (abaixo do `SummaryGrid`, acima do `CatalogTable`)
- [ ] Atualizar `useLiveOverview.ts` se necessário (tipagem)

## Acceptance Criteria

- [ ] `GET /api/live/overview` retorna `nodes: [...]` com dados de cada nó
- [ ] `NodesPanel` exibe 4 nós com status correto em `https://reports.dnor.io/`
- [ ] DiskPressure visível imediatamente sem abrir Coroot
- [ ] Não aumenta requests extras ao cluster — reutiliza fetch de `/api/v1/nodes` já existente
- [ ] Sem regressão no teste `cargo test` + `npm run build`

## References

- T-193 — DiskPressure master (diagnóstico feito sem painel por nó)
- T-195 — Cluster Pulse componentization (base de componentes)
- `apps/rs-observability-api/src/main.rs` — struct `NodeResource`, `build_live_summary`
- `apps/rs-observability-api/web-v2/src/components/` — componentes existentes
- `apps/rs-observability-api/web-v2/src/types/api.ts` — tipos de API

## Validação

```bash
# Backend: verificar nodes no JSON
curl https://reports.dnor.io/api/live/overview | jq '.nodes[] | {name, ready, disk_pressure}'

# Frontend: build sem erros
cd apps/rs-observability-api/web-v2 && npm run build

# Cargo tests sem regressão
cd apps/rs-observability-api && cargo test
```
