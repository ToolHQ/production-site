---
name: Operate K8s TUI
description: Guia de uso da interface principal de operações (k8s_ops_menu.sh).
---

# K8s Ops Menu

> [!IMPORTANT]
> **Governança**: Toda operação no cluster deve ser feita através deste menu.
> Se você precisar rodar um comando manual repetidamente, transforme-o em um script na pasta `scripts/` e integre-o aqui.
> **Não execute comandos ad-hoc fora da TUI.**

A TUI é o ponto de entrada para todas as operações administrativas.
Localização: `oci-k8s-cluster/k8s_ops_menu.sh`

## Menus Principais
1. **🔍 Node Status / Command Center**: Visualização de CPU/RAM, pods e acesso SSH direto.
2. **🛠️ Cluster Maintenance**: Auto-cura, correção de DNS, e limpeza de recursos caóticos.
3. **🚀 Component Management**: Instalação/Remoção de componentes core (Nexus, Elastic, Postgres).
4. **📊 Observability & Reports**: Acesso ao Dashboard K8s, Grafana e Relatórios HTML.

## Atalhos Úteis
- `Shift+D`: Dashboard Tunnel
- `Shift+K`: K9s Remoto
- `Ctrl+C`: Sair com segurança (fecha túneis)
