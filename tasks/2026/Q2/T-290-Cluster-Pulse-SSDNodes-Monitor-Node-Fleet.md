# T-290: Cluster Pulse — Monitoramento do Servidor SSD Nodes no Node Fleet

- **Status**: Backlog
- **Priority**: 🔼 High
- **Owner**: Antigravity
- **Epic**: Cluster Pulse / Observability
- **Est**: 6h

## Context

Acabamos de adquirir um novo servidor dedicado de alta performance na SSD Nodes (`ssdnodes-6a12f10c9ef11` / `104.225.218.78`). Para manter a visibilidade unificada da nossa frota de servidores (OCI, Hetzner, SSD Nodes), precisamos integrar esse novo servidor no painel "Node Fleet" do Cluster Pulse. Isso exige a instalação de agentes de coleta de métricas, roteamento de observabilidade no cluster e ajustes no backend/frontend do dashboard.

## Tasks

- [ ] Acessar o servidor SSD Nodes (`104.225.218.78`) e instalar/configurar o `prometheus-node-exporter` na porta 9100
- [ ] Configurar um `Endpoints` manual e um `Service` correspondente no namespace `coroot` do Kubernetes (ex: `ssdnodes-node-exporter`) apontando para o IP da SSD Nodes (`104.225.218.78:9100`)
- [ ] Validar a coleta das métricas da SSD Nodes (`104.225.218.78:9100`) no Prometheus do Coroot (verificar o target `health: up`)
- [ ] Atualizar a função `series_to_node_map` em `apps/rs-observability-api/src/main.rs` para reconhecer o IP da SSD Nodes e mapeá-lo para o hostname `"ssdnodes-monstro"`
- [ ] Atualizar o endpoint de `live_overview` em `apps/rs-observability-api/src/app.rs` para preencher as informações físicas do monstro (estimado: 4 vCPU, 8GiB RAM ou dados coletados via SSH) e integrá-lo homogeneamente na lista de nós
- [ ] Modificar o frontend Preact (`NodesPanel.tsx` e `types/api.ts`) para incluir e suportar o badge de cluster `SSD-NODES` (estilizado em roxo profundo ou violeta vibrante no `app.css`)
- [ ] Recompilar o frontend Vite, testar localmente a compilação do Rust e efetuar o deploy do app no cluster para validação final
