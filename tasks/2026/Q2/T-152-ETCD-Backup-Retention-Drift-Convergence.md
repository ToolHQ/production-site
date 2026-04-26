# T-152: ETCD Backup Retention Drift Convergence

- **Status**: Done
- **Priority**: High
- **Epic/Owner**: Infra
- **Estimation**: 3h
- **Closed**: 2026-04-25

## Context
Durante a execucao da [T-150](T-150-Master-Rootfs-Dependency-Reduction.md), a reducao do payload do
`MinIO` ficou bloqueada por um desvio operacional na retencao do ETCD:

- o bucket `k8s-backups/etcd` acumulava `22` snapshots logicos `etcd-*.db`, apesar da politica alvo ser
  manter apenas os `4` mais novos;
- o live ja nao refletia mais a IaC versionada em
  [components/backup/etcd-backup-cronjob.yaml](../../../components/backup/etcd-backup-cronjob.yaml):
  os CronJobs `etcd-backup` e `etcd-backup-prune` tinham sido sobrescritos para `rclone/rclone:latest`;
- o primeiro endurecimento da logica `mc` ainda tinha dois gaps reais descobertos no incidente:
  parser fragil de `mc ls` e dependencia de `awk`, inexistente no runtime `minio/mc`.

O resultado pratico era uma divergencia perigosa entre repo, cluster live e politica de retencao:
localmente `/var/backup/etcd` ja tinha convergido para `4` snapshots, mas o payload remoto no `MinIO`
continuava inflado e mascarava a capacidade real necessaria para o cutover do `MinIO` para Longhorn.

## Root Cause Confirmed

- a retencao do ETCD ainda dependia demais do caminho feliz de upload; por isso foi necessario manter
  um `CronJob` de prune independente;
- o formato real de `mc ls` inclui a coluna `STANDARD`, entao parsear por posicao fixa quebrava a
  selecao de `etcd-*.db`;
- `minio/mc` nao fornece `awk`, portanto um script que parecia funcionar em shell local falhava no
  runtime real do cluster;
- `set -e` sozinho nao protege contra falhas mascaradas em pipelines;
- aplicacoes manuais no cluster acabaram desviando os CronJobs live da IaC versionada, exigindo
  retomada explicita de ownership com Server-Side Apply.

## Repo Hardening Versioned

O manifesto versionado em
[components/backup/etcd-backup-cronjob.yaml](../../../components/backup/etcd-backup-cronjob.yaml)
foi ajustado para o comportamento que realmente sobrevive no runtime do cluster:

- `initContainer` em `alpine:3` instala `etcdctl`, remove `*.db.part` stale e salva o snapshot novo em
  `/var/backup/etcd`;
- o container principal `minio/mc` faz upload apenas do snapshot apontado por `latest_snapshot`;
- a selecao de objetos remotos passa a usar arquivos temporarios + extração do ultimo token da linha,
  sem `awk` e sem depender de pipeline para o `mc ls`;
- um `CronJob` separado (`etcd-backup-prune`) converge a retencao remota mesmo quando o job de backup
  nao roda no caminho feliz;
- artefatos legados (`*.db.part`, `latest_snapshot`, `test-write.txt`, `perm-check-*.txt`) sao limpos do
  bucket durante a rotina.

## Live Remediation Executed

- os CronJobs live foram restaurados a partir da IaC versionada via `kubectl apply --server-side
  --force-conflicts`, retomando ownership dos campos que tinham ficado sob `kubectl-client-side-apply`;
- jobs manuais usados durante a investigacao (`etcd-backup-manual-*` e `etcd-backup-prune-manual-*`)
  foram removidos antes da validacao final;
- foi executado um job manual `etcd-backup-validation`, com snapshot salvo e upload confirmado;
- foi executado um job manual `etcd-backup-prune-validation`, com prune remoto confirmado em logs;
- a validacao final foi feita por estado real do cluster (`get job`, `get pod`, `logs`), sem depender
  apenas de `kubectl wait`.

## Closure Evidence

- `etcd-backup` voltou para `schedule: 0 */6 * * *`, `initContainer: alpine:3` e `container: minio/mc`;
- `etcd-backup-prune` voltou para `schedule: 30 */6 * * *` e `container: minio/mc`;
- `etcd-backup-validation` e `etcd-backup-prune-validation` terminaram `Complete 1/1`;
- os logs do backup registraram `Removed myminio/k8s-backups/etcd/etcd-20260423-120006.db` durante o
  prune do bucket;
- `/data/minio/k8s-backups/etcd` convergiu para `4` snapshots logicos `etcd-*.db` e `~1019M`;
- `/var/backup/etcd` terminou com `4` snapshots `.db` e `latest_snapshot`, apontando para
  `etcd-20260425-211915.db`.

## Tasks
- [x] Confirmar que o live tinha derivado da IaC versionada para `rclone/rclone:latest`.
- [x] Corrigir o manifesto versionado para remover dependencia de `awk` e de parse fragil do `mc ls`.
- [x] Validar o manifesto corrigido com Server-Side Apply em `dry-run` antes de tocar o live.
- [x] Restaurar os CronJobs live a partir da IaC versionada com `--force-conflicts`.
- [x] Limpar os jobs manuais de troubleshooting que deixavam ruido operacional.
- [x] Executar um backup manual e um prune manual a partir dos CronJobs corrigidos.
- [x] Validar a convergencia final da retencao remota e local do ETCD.

## Residual Follow-up

- A retencao do `ETCD` deixou de ser o blocker principal da [T-150](T-150-Master-Rootfs-Dependency-Reduction.md).
  O restante da reducao do dataset do `MinIO` agora precisa focar em `backupstore`, payload do `Nexus`
  e no tamanho agregado ainda hospedado no rootfs do master.
- A borda HTTP segue desacoplada desta task e continua rastreada em
  [T-151](T-151-Ingress-Edge-Decoupling-from-Master.md).

## References
- [T-150](T-150-Master-Rootfs-Dependency-Reduction.md)
- [components/backup/etcd-backup-cronjob.yaml](../../../components/backup/etcd-backup-cronjob.yaml)
- [docs/backup-policy.md](../../../docs/backup-policy.md)
