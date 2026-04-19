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
5. **☁️ Cloud Rescue**: Operações OCI de emergência, diagnóstico de reachability e recuperação de acesso.

## Cloud Rescue

Use este menu quando o problema estiver no plano de acesso OCI, não dentro do Kubernetes.

Caso clássico: todas as instâncias seguem `RUNNING`, mas o SSH para `oci-k8s-master` e workers falha porque o IP atual da workstation não está mais autorizado na Security List.

Fluxo recomendado:

1. Abrir `Cloud Rescue`
2. Selecionar o nó afetado
3. Executar `Whitelist My IP (Fix SSH Block)`

Esse comando usa a integração OCI da própria TUI para descobrir a Security List ativa do subnet e adicionar o IP público atual como `/32` na porta 22. Em incidentes de bloqueio de SSH, prefira esse passo antes de reboot ou ações mais destrutivas.

## Atalhos Úteis

- `Shift+D`: Dashboard Tunnel
- `Shift+K`: K9s Remoto
- `Ctrl+C`: Sair com segurança (fecha túneis)
