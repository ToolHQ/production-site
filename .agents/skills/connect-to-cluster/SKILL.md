---
name: connect-to-cluster
description: Métodos oficiais e validados de conexão ao cluster OCI K8s (SSH, kubectl, TUI).
---

# Cluster Connectivity

> **REGRA**: Este procedimento DEVE ser executado no início de qualquer sessão que precise de `kubectl`. Sem o tunnel ativo, todos os comandos falham com `connection refused`.

## Infraestrutura SSH

`~/.ssh/config` já está pré-configurado com todos os nós. Chave: `~/.ssh/oci-ssh-key-2025-06-19.key`

| Alias            | IP Público       | Papel         |
| ---------------- | ---------------- | ------------- |
| `oci-k8s-master` | `150.136.34.254` | Control Plane |
| `oci-k8s-node-1` | `150.136.67.52`  | Worker        |
| `oci-k8s-node-2` | `150.136.70.212` | Worker        |
| `oci-k8s-node-3` | `150.136.88.87`  | Worker        |

## Método 1 — kubectl local (PADRÃO para novos chats)

**2 comandos, executar na ordem:**

```bash
# Passo 1: abrir tunnel SSH (background), local:6445 → master:6443
ssh -L 6445:localhost:6443 oci-k8s-master -N -f

# Passo 2: apontar kubectl para o kubeconfig do tunnel
export KUBECONFIG=/home/ToolHQ/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml
```

**Verificação:**

```bash
kubectl get nodes
# Esperado: k8s-master, k8s-node-1, k8s-node-2, k8s-node-3 — todos Ready
```

**Encerrar tunnel:**

```bash
pkill -f "ssh.*-L.*6445"
```

> **Arquivos de referência:**
>
> - Tunnel: `oci-k8s-cluster/kubeconfig_tunnel.yaml` → `127.0.0.1:6445`
> - Direto no master: `oci-k8s-cluster/kubeconfig.yaml` → `127.0.0.1:6443`

## Método 2 — SSH direto a um nó

```bash
ssh oci-k8s-master   # Control plane
ssh oci-k8s-node-1   # Worker 1
ssh oci-k8s-node-2   # Worker 2
ssh oci-k8s-node-3   # Worker 3
```

> Evite modificar arquivos diretamente nos nós. Use a TUI ou `kubectl` sempre que possível.

## Método 3 — Via TUI

```bash
cd /home/ToolHQ/production-site/oci-k8s-cluster
./k8s_ops_menu.sh
```

A TUI gerencia tunnels automaticamente para Dashboard (porta 8443) e port-forwards de serviços.
Ela também expõe o fluxo de resgate de conectividade OCI quando a porta 22 estiver bloqueada para o seu IP atual.

## Resgate de SSH bloqueado

Use este fluxo quando as instâncias continuarem `RUNNING`, mas `ssh oci-k8s-master` e afins falharem por timeout ou bloqueio na porta 22.

```bash
cd /home/ToolHQ/production-site/oci-k8s-cluster
./k8s_ops_menu.sh
```

Na TUI:

1. Entrar em `Cloud Rescue`
2. Selecionar o nó afetado
3. Executar `Whitelist My IP (Fix SSH Block)`

Esse caminho chama a rotina OCI `whitelist_my_ip()` e adiciona o IP público atual da workstation como regra `/32` na Security List do subnet, liberando SSH na porta 22 sem depender de acesso prévio ao nó.

## Troubleshooting

| Sintoma                            | Causa                                             | Solução                                                       |
| ---------------------------------- | ------------------------------------------------- | ------------------------------------------------------------- |
| `connection refused` na porta 6445 | Tunnel não ativo                                  | Executar Passo 1 acima                                        |
| `connection refused` na porta 6443 | Tunnel ativo mas porta errada                     | Usar `kubeconfig_tunnel.yaml`, não `kubeconfig.yaml`          |
| SSH timeout                        | Security List OCI sem o seu IP / IP público mudou | Usar TUI → `Cloud Rescue` → `Whitelist My IP (Fix SSH Block)` |
| `certificate expired`              | Certs kubeadm vencidos (>1 ano)                   | `kubectl certificate renew` no master                         |
