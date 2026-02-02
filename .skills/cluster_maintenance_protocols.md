---
name: Cluster Maintenance Protocols
description: Como usar scripts de manutenção para resolver problemas comuns.
---

# Cluster Maintenance Scripts

Estes scripts estão em `oci-k8s-cluster/scripts/maintenance/` e são acessíveis via TUI > Cluster Maintenance.

| Script | Função | Quando usar |
|--------|--------|-------------|
| `clean_cluster_chaos.sh` | Remove Pods Evicted/Failed/Unknown | Quando o cluster está "sujo" após falhas. |
| `prune_disk.sh` | `docker system prune` / `crictl rmi` | Quando houver *DiskPressure* no Master. |
| `fix_registry_hosts.sh` | Mapeia dinamicamente o IP do Nexus em `/etc/hosts` | Se ocorrerem erros de `ImagePullBackOff`. |
| `dns_doctor.sh` | Reinicia CoreDNS e valida resolução | Se serviços internos não se encontrarem. |
| `full_cluster_heal.sh` | Reinicia CNI, Kubelet e Containerd | "Nuclear option" para nós travados. |
