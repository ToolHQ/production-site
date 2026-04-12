---
name: Storage Operations
description: Diagnóstico de discos cheios e gestão de PVCs.
---

# Storage Management

## Diagnóstico
Se um nó reportar `DiskPressure`:
1. Execute `scripts/observability/generate_storage_dossier.sh`.
2. O relatório identificará quem consome espaço (`/var/lib/docker`, `/var/log`, PVs).

## Longhorn (CSI)
Os volumes persistem em `/var/lib/longhorn` nos nós.
- Backup: Configurado para Minio (S3).
- Snapshots: Podem encher o disco. Use a UI do Longhorn (via TUI) para limpar snapshots antigos.

## PostgreSQL
Os bancos usam StatefulSets com PVCs.
- `statefulset.yaml`: Define o PVC template.
- Para aumentar disco: Edite o PVC *antes* de editar o StatefulSet (se suportado pela StorageClass) ou use migração manual.
