# T-307: OCI Longhorn disk headroom e política preventiva

- **Status**: Done
- **PR**: feat/t-307-longhorn-headroom
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 1d

## Context

O health watchdog reportou headroom baixo nos discos Longhorn: master ~10G livres, node-1 ~11G, node-3 ~14G, todos abaixo do warning de 15G. Não há volumes degradados, mas o histórico do cluster mostra incidentes de DiskPressure e Longhorn sensível a falta de espaço.

Essa tarefa deve transformar o alerta em prevenção: capacity model, threshold consistente, painéis/TUI e ações seguras antes de chegar em DiskPressure.

## Tasks

- [x] Coletar uso por nó: rootfs (SSH) + Longhorn `storageAvailable` via kubectl.
- [x] Top volumes por `actualSize` no relatório.
- [x] Thresholds warning 15GiB / critical 10GiB (alinhado `cluster_health_check.sh`).
- [x] Diagnóstico TUI: Maintenance → item 11 + script `longhorn_headroom_diag.sh`.
- [x] Runbook existente: `RUNBOOK_STORAGE_HEADROOM.md`.
- [x] Harness `validate_longhorn_headroom_diag.sh` PASS live.

## Validação

```bash
kubectl get volumes.longhorn.io -n longhorn-system -o wide
kubectl get nodes
for n in oci-k8s-master oci-k8s-node-1 oci-k8s-node-2 oci-k8s-node-3; do ssh "$n" "df -h / /var/lib/longhorn 2>/dev/null"; done
```

Critério de aceite: relatório/TUI apontando causa do headroom baixo e plano de ação seguro versionado.
