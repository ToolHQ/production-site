---
name: Connect to Cluster
description: Métodos oficiais de conexão ao cluster (SSH, VPN, TUI).
---

# Cluster Connectivity

O acesso ao cluster é estritamente controlado via SSH Keys e Túneis.

## 1. Pré-requisitos
- Chave SSH configurada em `~/.ssh/id_rsa` (ou similar) autorizada nos nós OCI.
- Arquivo `~/.ssh/config` com alias para os nós (ex: `oci-k8s-master`).

## 2. Métodos de Conexão

### A. Via TUI (Recomendado)
A TUI (`k8s_ops_menu.sh`) gerencia automaticamente os túneis para serviços:
- **Dashboard**: Use `Shift+D` para abrir túnel na 8443.
- **Serviços**: Use o menu *Access & Port Forwarding* para expor services locais.

### B. Via VPN (WSL/Linux)
Se estiver usando WSL ou precisar de acesso direto à rede de pods/serviços:
```bash
sudo systemctl restart wsl-vpnkit
```
Isso garante que a rede do WSL consiga rotear para os IPs do cluster.

### C. Acesso SSH Direto
Apenas para debug profundo (SysAdmin):
```bash
ssh oci-k8s-master
```
*Nota: Evite alterar arquivos diretamente nos nós. Use a TUI.*

## 3. Kubeconfig
O arquivo `kubeconfig.yaml` local aponta para `127.0.0.1:6445`.
A TUI ou um túnel manual (`ssh -L 6445:localhost:6443 ...`) deve estar ativo para que o `kubectl` local funcione.
