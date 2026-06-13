# SSD Nodes - Guia de Conexão e Operação

## 📋 Informações do Servidor

| Atributo        | Valor                          |
|-----------------|--------------------------------|
| **Provider**    | SSD Nodes (Dedicated)          |
| **IP Público**  | `104.225.218.78`               |
| **Tailscale IP**| `100.92.199.93`                |
| **SSH Host**    | `ssdnodes-6a12f10c9ef11`       |
| **Alias Legacy**| `ssdnodes-monstro`             |
| **Hardware**    | x86_64, 12 vCPU / 60GB RAM / 1.2TB disk |
| **Usuário SSH** | `root`                         |
| **Chave SSH**   | `~/.ssh/id_rsa`                |

## 🚀 Conexão Rápida

### Pré-requisitos
- Chave SSH `~/.ssh/id_rsa` configurada
- Acesso à rede (IP público ou Tailscale)

### 1. Instalar configuração SSH (uma vez)
```bash
bash oci-k8s-cluster/scripts/ssdnodes/install_ssdnodes_ssh_config.sh
```

### 2. Conectar via SSH
```bash
# Usando alias configurado
ssh ssdnodes-6a12f10c9ef11

# Ou via IP direto
ssh root@104.225.218.78

# Via Tailscale (se estiver na rede Tailscale)
ssh root@100.92.199.93
```

### 3. Script de Conexão Rápida
```bash
# Relatório rápido do servidor
./scripts/connect-ssdnodes.sh --status

# Executar comando remoto
./scripts/connect-ssdnodes.sh --cmd "uptime"

# Acessar cluster K8s
./scripts/connect-ssdnodes.sh --kube

# SSH interativo
./scripts/connect-ssdnodes.sh
```

## ☸️ Kubernetes Cluster

### Kubeconfig Local
```bash
export KUBECONFIG=~/.kube/ssdnodes.yaml
kubectl get nodes
```

### Serviços no Cluster
| Serviço           | URL                                  |
|-------------------|--------------------------------------|
| MinIO Console     | https://minio.ssdnodes.dnor.io       |
| MinIO S3 API      | https://s3.ssdnodes.dnor.io          |
| K8s Dashboard     | https://k8s.ssdnodes.dnor.io         |
| Kubecost          | https://cost.ssdnodes.dnor.io        |
| SonarQube CE      | https://sonar.ssdnodes.dnor.io       |
| Jenkins CI        | https://jenkins.ssdnodes.dnor.io     |
| n8n Automation    | https://n8n.ssdnodes.dnor.io         |

## 🔧 Scripts de Operação

| Script | Descrição |
|--------|-----------|
| `oci-k8s-cluster/scripts/ssdnodes/install_ssdnodes_ssh_config.sh` | Instala config SSH |
| `oci-k8s-cluster/scripts/ssdnodes/deploy_ssdnodes_components.sh` | Deploy componentes K8s |
| `oci-k8s-cluster/scripts/hardening/ssh_harden_ssdnodes.sh` | Hardening SSH |
| `scripts/connect-ssdnodes.sh` | Conexão rápida e relatórios |

## 🔒 Segurança

- **Autenticação**: Apenas chave SSH (senha desabilitada)
- **Fail2ban**: Ativo para proteção contra brute-force
- **UFW**: Firewall configurado com acesso restrito
- **Tailscale**: Disponível para acesso via rede privada

### Portas Liberadas
| Porta   | Acesso                    |
|---------|---------------------------|
| 22/tcp  | Global (com fail2ban)     |
| 80/443  | ADMIN + INGRESS IPs + Tailscale |
| 6443    | ADMIN apenas              |
| 9100    | OCI IPs (Prometheus)      |
| 8443    | ADMIN + INGRESS + Tailscale |

## 📊 Status Atual (Última Verificação)

```
Hostname:  ssdnodes-6a12f10c9ef11
Uptime:    up 20 days
CPU:       12 cores | Load: 12.76, 10.49, 9.89
Memory:    7.6Gi / 60Gi used
Disk:      46G / 1.2T used (5%)
K8s Node:  Ready (v1.33.12)
Tailscale: 100.92.199.93
```

## 📚 Documentação Relacionada

- `components/ssdnodes/README.md` - Documentação principal do componente
- `components/ssdnodes/RUNBOOK_SSH_INCIDENT.md` - Resposta a incidentes SSH
- `components/ssdnodes/tailscale-setup.md` - Configuração Tailscale
- `oci-k8s-cluster/scripts/ssdnodes/README.md` - Referência de scripts
