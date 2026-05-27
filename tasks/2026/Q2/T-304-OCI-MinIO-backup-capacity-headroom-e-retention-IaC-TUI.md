# T-304: OCI MinIO backup capacity headroom e retention IaC/TUI

- **Status**: Backlog
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

- [ ] Capturar inventário detalhado de `/data` por prefixo, idade e crescimento (`k8s-backups`, `nexus`, outros).
- [ ] Mapear quais CronJobs/escritas alimentam cada prefixo e qual retenção já está codificada.
- [ ] Definir política alvo: warning/critical, retenção diária/semanal e janela segura de prune.
- [ ] Implementar prune/retention em manifesto/script versionado, com modo `--dry-run` obrigatório.
- [ ] Integrar ação na TUI em menu de Backup/Storage: diagnóstico, dry-run, aplicar e rollback/restore guidance.
- [ ] Atualizar documentação/runbook com causa raiz, comandos de verificação e regra para evitar limpeza manual sem IaC.
- [ ] Validar queda do uso para zona segura (<75%) e confirmar que backups Longhorn continuam `Completed`.

## Validação

Comandos esperados:

```bash
kubectl exec -n minio <pod> -- df -h /data
kubectl exec -n minio <pod> -- du -sh /data/*
kubectl get backups.longhorn.io -n longhorn-system
kubectl get cronjob -n minio minio-capacity-watchdog
```

Critério de aceite: MinIO abaixo de 75%, prune reproduzível por IaC/TUI, watchdog sem falhas novas e documentação atualizada.
