# T-289: Cluster Pulse — Monitoramento do Hetzner Runner no Node Fleet com Marcador de Cluster

- **Status**: Backlog
- **Priority**: 🔼 High
- **Owner**: Antigravity
- **Epic**: Cluster Pulse / Observability
- **Est**: 6h

## Context

Queremos estender o painel "Node Fleet" da seção de infraestrutura para monitorar também o uso real (CPU, Mem, Disco, Alertas) do nosso servidor remoto de build na Hetzner (`hetzner-cax21-helsinki`), exibindo-o na mesma tabela de nós de forma homogênea. Também precisamos adicionar uma coluna/marcador para categorizar visualmente se o nó pertence ao cluster `OCI-K8S` ou ao provedor `HETZNER`.

## Tasks

- [ ] Instalar e configurar o `node-exporter` na máquina física do Hetzner (`37.27.85.100`) na porta 9100
- [ ] Configurar um `Endpoints` manual + `Service` no namespace `observability` no Kubernetes para expor o node-exporter externo do Hetzner ao Prometheus do cluster
- [ ] Validar a coleta das métricas da instância `37.27.85.100:9100` no Prometheus do Coroot
- [ ] Atualizar o backend Rust (`apps/rs-observability-api/src/main.rs`) para reconhecer as métricas do IP do Hetzner no HashMap de `node_metrics`
- [ ] Modificar o frontend (`NodesPanel.tsx`) para incluir a coluna "Cluster" com badges estilizados (`OCI-K8S` em azul/verde e `HETZNER` em laranja)
- [ ] Injetar os dados da máquina Hetzner na lista do painel "Node Fleet" e validar a exibição homogênea e tooltips das sparklines
