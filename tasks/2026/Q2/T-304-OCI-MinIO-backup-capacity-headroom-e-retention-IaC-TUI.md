# T-304: OCI MinIO backup capacity headroom e retention IaC/TUI

- **Status**: Done
- **Priority**: 🚨 Critical
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 1d

## Context

A varredura de 2026-05-27 encontrou o MinIO do cluster OCI com `/data` em **92%** (`11G/12G`), acima do limite crítico do runbook. O uso principal está em `k8s-backups` (~6.6G) e `nexus` (~4.2G). O watchdog `minio-capacity-watchdog` voltou a completar, mas há jobs históricos `Failed` e a capacidade já está no ponto de risco.

Qualquer correção deve virar produto de infraestrutura: retenção, prune e thresholds precisam estar codificados em IaC/TUI, não como limpeza manual sem rastro. A TUI deve expor diagnóstico, dry-run e execução controlada para aprendermos e prevenir nova recorrência.

Arquivos/caminhos candidatos:

- `components/minio/`, `components/backup/`, `components/longhorn/`
- `oci-k8s-cluster/k8s_ops_menu.sh`
- `oci-k8s-cluster/scripts/observability/`
- `oci-k8s-cluster/scripts/*backup*`, se existir

## Tasks

- [x] Inventário: `k8s-backups` 6.6G (backupstore 5.6G + etcd 1G), `nexus` 4.2G (blob store — não prunear).
- [x] Fontes: Longhorn `backup-daily` retain=3, `etcd-backup-prune`, `minio-capacity-watchdog`; réplica postgres tinha regressão T-223.
- [x] Script `scripts/backup/prune_minio_backup_capacity.sh` (`--dry-run` / `--apply`, retain=3).
- [x] TUI Backup → opção 11 (diagnose + apply).
- [x] Aplicado: 10 backup CRs removidos + label recurring off na réplica postgres; GC Longhorn liberou espaço.
- [x] Validar <75% — **55%** em `/data` (6.4G/12G) verificado 2026-06-09 via `kubectl exec` MinIO pod.
- [x] `components/backup/README.md` documenta prune T-304 (opção 11 TUI).

## Validação

Comandos esperados:

```bash
kubectl exec -n minio <pod> -- df -h /data
kubectl exec -n minio <pod> -- du -sh /data/*
kubectl get backups.longhorn.io -n longhorn-system
kubectl get cronjob -n minio minio-capacity-watchdog
```

Critério de aceite: MinIO abaixo de 75%, prune reproduzível por IaC/TUI, watchdog sem falhas novas e documentação atualizada.
