# T-124: Backup Retention Audit & ETCD Recovery

- **Status**: Done (ETCD/GDrive recovered; retention converged; Nexus policy documented)
- **Priority**: 🚨 Critical
- **Owner**: Infra
- **Est.**: 3h
- **Created**: 2026-04-15

---

## Context

### Situação atual (snapshot 2026-04-15)

Análise executiva do storage de backup revelou problemas críticos e oportunidades de otimização:

#### 🗄️ MinIO (in-cluster) — 16.3 GiB total

| Bucket        | Tamanho | Objetos |
| ------------- | ------- | ------- |
| `k8s-backups` | 12 GiB  | 11,222  |
| `nexus`       | 4.3 GiB | 3,908   |

**Top consumidores em `k8s-backups/backupstore/volumes/`:**

| Serviço                    | Tamanho     | Objetos | PVC                     |
| -------------------------- | ----------- | ------- | ----------------------- |
| coroot-data                | **3.9 GiB** | 3,633   | pvc-efbe8d2c (coroot)   |
| kubecost-prometheus-server | **1.2 GiB** | 980     | pvc-76755523 (kubecost) |
| nexus-pvc                  | 112 MiB     | 288     | pvc-229e3768 (nexus)    |
| kubecost-cost-analyzer     | 74 MiB      | 436     | pvc-3a209369 (kubecost) |
| postgres-data-postgres-1   | 14 MiB      | 89      | pvc-901a3108 (postgres) |
| postgres-data-postgres-0   | 12 MiB      | 75      | pvc-fd9d35d1 (postgres) |
| coroot-clickhouse          | 304 KiB     | 26      | pvc-23ab203e (coroot)   |

#### ☁️ Google Drive (rclone)

| Pasta                      | Status          | Última sync |
| -------------------------- | --------------- | ----------- |
| `k8s-backups/backupstore/` | Mirror do MinIO | 2025-11-27  |
| `k8s-backups/etcd/`        | 🔴 VAZIO        | 2026-01-02  |

#### CronJobs de backup configurados

| Job                      | Schedule      | Última execução  | Status      |
| ------------------------ | ------------- | ---------------- | ----------- |
| `longhorn backup-daily`  | `0 1 * * *`   | 2026-04-15 01:00 | ✅ OK       |
| `etcd-backup`            | `0 */6 * * *` | **2026-02-21**   | 🔴 QUEBRADO |
| `postgres-auto-snapshot` | `0 */6 * * *` | correndo         | ✅ OK       |

---

### 🚨 Problemas Críticos

1. **ETCD backup completamente quebrado há 53 dias**
   - Último run: 21/02/2026
   - `k8s-backups/etcd/` no MinIO está **VAZIO**
   - `/host-backup/etcd/` não existe em nenhum nó
   - O job depende deste path para ler o snapshot e fazer upload
   - **Risco**: perda total do control plane sem backup recuperável
   - Diagnóstico necessário: o job está falhando silenciosamente? O snapshot etcd deixou de ser gerado no host?

2. **Pipeline ETCD com staging incorreto**
   - O CronJob atual monta `/data/minio/k8s-backups` como `hostPath`
   - Isso grava snapshots diretamente no backend filesystem do bucket MinIO
   - O upload subsequente via `mc cp` tenta reenviar o mesmo objeto e falha com `AccessDenied`
   - O staging correto precisa ficar fora do datadir do MinIO (ex.: `/var/backup`)

3. **GDrive sync desatualizado (~4 meses)**
   - `backupstore/` no GDrive não é atualizado desde Nov/2025
   - Não há rclone cronjob visível no cluster
   - Off-site backup essencialmente inexistente

---

### 💡 Oportunidades de Otimização

- **coroot-data (3.9 GiB)**: dados de observabilidade não precisam de retenção > 7 backups. Verificar se o `backup-daily` com `retain: 7` está sendo respeitado ou se volumes órfãos não são limpos.
- **kubecost volumes (1.3 GiB)**: kubecost é ferramenta de custo monitoring, não dado crítico. Avaliar reduzir retenção ou excluir do grupo `default` do Longhorn backup.
- **nexus bucket (4.3 GiB)**: sem política de retenção visível. Artifacts antigos acumulando.
- **Postgres snapshots**: 8 VolumeSnapshots existem (retention=7), funcionando corretamente. Porém há snapshots manuais de dez/2025 que podem ser removidos.

### Update 2026-04-18 — Hardening e causa-raiz do backlog atual

- O relatório bruto do watchdog estava superestimando o incidente: `VolumeAttachment` com `status.attached=true` estava sendo marcado como "stuck attaching", e pods terminais históricos (`Failed` / `Succeeded`) estavam entrando como erro atual.
- O problema real em produção ficou concentrado no control plane: `k8s-master` entrou em `DiskPressure=True` em `2026-04-17`, com taint `node.kubernetes.io/disk-pressure:NoSchedule`.
- O primeiro job degradado (`etcd-backup-29606760`) foi evicted por `ephemeral-storage`; os ciclos seguintes ficaram `Pending` porque o CronJob fixa `nodeSelector` no control-plane e não tolera `disk-pressure`.
- O acúmulo virou backlog porque o CronJob estava com `concurrencyPolicy: Allow`, então cada janela de 6h abriu mais um Job ativo/pendente.
- O staging local em `/var/backup` estava em `2.1G` no master; isso não explica sozinho o uso do rootfs, mas foi suficiente para empurrar um nó já apertado abaixo do threshold do kubelet.
- Hardening aplicado no repo e no cluster:
  - `concurrencyPolicy: Forbid`
  - `startingDeadlineSeconds: 1800`
  - `backoffLimit: 1`
  - `activeDeadlineSeconds: 1800`
  - `ttlSecondsAfterFinished: 21600`
  - `successfulJobsHistoryLimit: 1`
  - `failedJobsHistoryLimit: 1`
  - resources explícitos para init/upload
  - retenção local reduzida para os `4` snapshots mais novos (`~24h`)
- O backlog ativo de Jobs do `etcd-backup` foi limpo; restam apenas artefatos terminais/orfãos em garbage collection e o `DiskPressure` do master como pendência operacional viva.
- Último sucesso confirmado do CronJob continua em `2026-04-17T00:00:47Z` até o master sair de `DiskPressure`.

### Update 2026-04-18 — Cluster recovery drill-down (master DiskPressure)

- O `DiskPressure` do `k8s-master` não vinha principalmente de `/var`; o maior consumidor do rootfs foi confirmado em `/data/minio` com **25G** locais no mesmo disco do sistema.
- Havia ainda **6.7G** de cache rootless do BuildKit em `/home/ubuntu/.local/share/buildkit`; esse volume não era limpo pelo `clean_node.sh` rodado como `root`.
- Mitigação segura já aplicada:
  - prune do BuildKit rootless do usuário `ubuntu`, preservando `1G` de cache e recuperando **6.19G**;
  - rootfs do master caiu de `86%` / `7G` livres para `74%` / `13G` livres;
  - `ingress-nginx` e `minio` deixaram de tolerar `node.kubernetes.io/disk-pressure` no repo e no cluster, para parar o loop infinito de `Evicted`;
  - limpeza cluster-wide dos pods `Failed` / `Evicted` / `Succeeded`, reduzindo o ruído operacional e liberando quota do namespace `ingress-nginx`;
  - `kubecost-quota` foi ajustada para `requests.cpu=250m` e `requests.memory=1536Mi`, destravando a criação do `kubecost-prometheus-server` em worker.
- Residual atual:
  - o kubelet ainda mantém `DiskPressure=True` no master e reaplica o taint mesmo com `node.fs.availableBytes=12985929728` (~13G) no `stats/summary`;
  - `ingress-nginx` e `minio` agora entram em `Pending` (sem churn), mas continuam bloqueados enquanto o kubelet não retirar a condição;
  - `kubecost-prometheus-server` já saiu de `FailedCreate` por quota e foi agendado em `k8s-node-2`.
- Causa-raiz estrutural que permanece para prevenção:
  - o MinIO continua em `hostPath` no master (`/data/minio`), consumindo rootfs local e tornando o control-plane vulnerável a novo `DiskPressure` conforme o bucket cresce.
- Follow-up recomendado após estabilização imediata:
  - validar por que o kubelet não baixou a condição mesmo com `nodefs/imagefs` saudáveis;
  - planejar migração do storage do MinIO para volume fora do rootfs do master.
- Estado validado ao final da mitigação imediata:
  - `k8s-master` voltou para `DiskPressure=False` e manteve apenas o taint normal de `control-plane`;
  - `ingress-nginx-controller`, `minio-deployment` e `kubecost-prometheus-server` ficaram novamente em `1/1`;
  - namespaces `ingress-nginx` e `minio` ficaram sem pods `Failed` remanescentes;
  - o `kubecost-prometheus-server` exigiu limpeza manual de um attachment órfão do Longhorn (`attachmentTickets[""]` do tipo `longhorn-api`) antes de voltar a anexar o PVC em `k8s-node-2`.

### Update 2026-04-18 — ETCD path back online

- O CronJob voltou a produzir snapshot local no master: `/var/backup/etcd/etcd-20260418-180018.db`.
- O run `etcd-backup-29608920` concluiu com sucesso e o objeto correspondente apareceu no MinIO em
  `k8s-backups/etcd/etcd-20260418-180018.db`.
- O job `etcd-backup-29604240` permanece apenas como histórico falho anterior; nao representa backlog ativo.
- O `gdrive-sync.timer` esta habilitado e aguardando a proxima janela em `2026-04-19 03:30 UTC`.
  A validacao off-site continua sendo o gate final de fechamento da task.

### Update 2026-04-19 — Off-site freshness revalidated, retention drift isolated

- O `gdrive-sync.service` no master falhou nos ciclos de `2026-04-17` e `2026-04-18`, mas o run de
  `2026-04-19 03:30 UTC` concluiu com sucesso, incluindo archive do `backupstore`, upload de ETCD,
  prune remoto no GDrive e prune local no staging.
- O remoto `gdrive:k8s-backups/etcd` agora mostra snapshots recentes ate `etcd-20260419-060005.db`
  e tamanho total de `2.983 GiB` (`12` objetos), o que fecha o gate de frescor off-site.
- O mapeamento live de `volumes.longhorn.io` esta coerente com a politica do repo:
  - `nexus` e `postgres` seguem no grupo `default`;
  - `coroot` e `kubecost` ja estao rotulados no grupo `observability`.
- O backlog residual em `k8s-backups` ficou isolado em duas frentes:
  - volumes de observability ainda carregam `10` backups historicos herdados do periodo anterior ao
    split `default` -> `observability`, portanto exigem cleanup retroativo se quisermos convergir para `retain: 3` agora;
  - `k8s-backups/etcd/` no MinIO ainda acumulava snapshots antigos e artefatos legados `*.db.part`,
    porque o CronJob podava apenas o staging local e o GDrive, nao o prefixo ETCD no bucket MinIO.
- O inventario de `BackupVolume` continua com `11` roots sem volume Longhorn live correspondente,
  todos candidatos a cleanup historico separado:
  `pvc-024bef7e-a0a8-49cc-8632-f8827260217c`, `pvc-07028b00-5d63-4112-84e9-126faee4f6ce`,
  `pvc-527009d1-6f72-4e1d-91e7-7bf74a60bd09`, `pvc-587154bf-86a4-40d4-8339-f33a0e082fd5`,
  `pvc-6a1e78ec-ca37-4d2d-91ae-61eb15be0e3a`, `pvc-70ca900b-bf13-4b79-9cc7-91e35dc06f71`,
  `pvc-76d32043-c899-4346-a276-c4ad0b20a030`, `pvc-8849d366-6900-489d-94bd-88e17ef269f9`,
  `pvc-9457cf3d-b57a-4148-9935-922998049c99`, `pvc-b48937cd-c9ee-40e1-ab42-ddc5b3130478`,
  `pvc-c6f50016-a36d-410b-bc17-292f9e4ff805`.

### Update 2026-04-19 — Cleanup execution after approval

- O `CronJob` `etcd-backup` foi reaplicado com pruning no upload para MinIO; o primeiro rerun manual
  revelou que a imagem `minio/mc` nao tem `awk`, entao o manifest foi corrigido para parsing shell puro.
- Foram executados dois Jobs manuais (`etcd-backup-manual-191337` e `etcd-backup-manual-rerun-191521`) para
  validar o path suportado; os snapshots novos `etcd-20260419-221343.db` e `etcd-20260419-221527.db`
  ficaram preservados.
- O prefixo ETCD no backend local foi limpo com criterio conservador e ficou reduzido a exatamente quatro
  snapshots validos:
  - `etcd-20260419-120005.db`
  - `etcd-20260419-180005.db`
  - `etcd-20260419-221343.db`
  - `etcd-20260419-221527.db`
- Artefatos legados de backend (`*.db.part`, `latest_snapshot` e snapshots antigos que ja nao existiam via API)
  foram removidos explicitamente do master apos validacao de que nao estavam mais expostos pelo S3 API.
- Os cinco volumes de observability convergiram imediatamente para `3` backups cada:
  - `coroot-clickhouse` (`pvc-23ab203e...`) -> `3`
  - `coroot-prometheus-server` (`pvc-2b52212e...`) -> `3`
  - `kubecost-cost-analyzer` (`pvc-3a209369...`) -> `3`
  - `kubecost-prometheus-server` (`pvc-76755523...`) -> `3`
  - `coroot-data` (`pvc-efbe8d2c...`) -> `3`
- Os `11` roots orfaos de `BackupVolume` foram tratados:
  - `10` roots vazios foram deletados diretamente;
  - o root remanescente `pvc-76d32043...` (Elastic historico) teve seus `6` backups antigos removidos e o
    `BackupVolume` correspondente foi deletado.
- Inventario Longhorn apos a convergencia desta rodada: `8` `BackupVolume`, todos correspondentes aos `8`
  volumes live do cluster.
- Residual imediato apos esta rodada:
  - `backupstore` ainda media ~`17 GiB` antes da auditoria final do namespace `postgres`;
  - o backlog restante ficou reduzido aos snapshots manuais antigos do namespace `postgres` e a validacao
    de que o `postgres-data-postgres-0` com `14` backups era ou nao aderente a politica atual.

### Update 2026-04-19 — Postgres residual fechado e meta de capacidade atingida

- Os `VolumeSnapshot` manuais legados do namespace `postgres` foram removidos com criterio conservador:
  - `manual-20251201-090155` (`postgres-pvc`)
  - `manual-20251201-091805` (`postgres-pvc-green`)
  - `postgres-pvc-restored-snap-20251213-125934` (`postgres-pvc-restored`)
- Os tres PVCs de origem ja nao existem no cluster, e os `VolumeSnapshotContent` correspondentes usavam
  `deletionPolicy: Delete`; o garbage collection removeu os tres conteúdos CSI imediatamente apos o delete.
- Nao restaram `backups.longhorn.io` associados aos handles antigos, entao essa limpeza ficou restrita a
  artefatos historicos de recuperacao e nao afetou a politica ativa.
- O `postgres-data-postgres-0` permaneceu com `14` backups, e isso foi validado como comportamento esperado:
  `7` backups diarios do `backup-daily` + `7` backups criados pelos `VolumeSnapshot` de 6h (`bak://...`).
- Medicao final validada diretamente no pod do MinIO:
  - `/data/k8s-backups` = `8055 MiB`
  - `/data/k8s-backups/backupstore` = `7036 MiB`
  - `/data/k8s-backups/etcd` = `1019 MiB`
- Com isso, a meta operacional da task para `k8s-backups` ficou atendida (`8055 MiB < 8192 MiB`, isto e,
  abaixo de `8 GiB`).
- Residual observado no control-plane do Longhorn: o sync do `BackupTarget` recriou `10` `BackupVolume`
  vazios (sem `lastBackupName`, `size` ou `dataStored`) a partir de metadata residual. Eles nao representam
  payload retido ativo e nao impedem a convergencia de capacidade.
- Pendencias reais que ainda sobraram nesta task:
  - definir/documentar politica do bucket `nexus`;
  - consolidar a documentacao dedicada da politica de backup (`docs/backup-policy.md`);
  - atualizar o KANBAN quando a task for formalmente encerrada.

### Update 2026-04-19 — Politica do bucket Nexus codificada

- O bucket `nexus` no MinIO foi validado como storage ativo do blob store S3 `minio` do Nexus, nao como
  backlog de backup: inventario live medido em `4.3 GiB` e `3908` objetos, todos sob o prefixo
  `nexus/content`.
- O repo ja criava esse blob store via `oci-k8s-cluster/lib/nexus_init.sh` apontando o bucket `nexus`
  com `expiration: -1`, e os repositorios `docker-repo`, `npm-repo`, `npm-proxy` e `npm-group` seguem
  amarrados a esse blob store.
- Politica definida: nao existe pruning por idade/tamanho no nivel do MinIO para `nexus/`; qualquer
  retencao futura precisa acontecer por cleanup policy do proprio Nexus, nunca por `mc rm` ou delete
  direto no backend do bucket.
- Foi criada a documentacao consolidada em `docs/backup-policy.md`, incluindo a distincao entre dados de
  backup (`k8s-backups`) e dados operacionais vivos do Nexus (`nexus`).
- Com isso, o escopo tecnico de T-124 fica encerrado: a convergencia de capacidade do `k8s-backups` foi
  validada, o bucket `nexus` foi classificado corretamente, e a politica resultante ficou documentada.

---

## Tasks

### 🔴 Fase 1 — ETCD Recovery (Crítico — fazer PRIMEIRO)

- [x] **1.1** Investigar por que `/host-backup/etcd/` não existe nos nós
  - Verificar se há systemd timer/script que gera o snapshot etcd no host
  - Checar se o path foi montado no `etcd-backup` CronJob (hostPath volume)
- [x] **1.2** Verificar logs do `etcd-backup` job no kube-system
  - `kubectl logs -n kube-system -l job-name=etcd-backup` dos últimos runs
  - Identificar o erro exato
- [x] **1.3** Reparar o pipeline etcd → MinIO
  - Opção A: restaurar script de snapshot no host (se era externo ao cronjob)
  - Opção B: refatorar o cronjob para usar `etcdctl snapshot save` diretamente
- [x] **1.4** Validar: executar job manualmente e confirmar upload no MinIO
- [x] **1.5** Atualizar `components/backup/etcd-backup-cronjob.yaml` com a correção
- [x] **1.6** Corrigir backlog guard do CronJob e reduzir staging local para rootfs apertado
- [x] **1.7** Restaurar novo run bem-sucedido após o master sair de `DiskPressure`

### 🟡 Fase 2 — GDrive Sync Recovery

- [x] **2.1** Verificar se existe rclone cronjob/systemd timer ativo no cluster ou no master
  - `kubectl get cronjob -A | grep rclone`
  - `systemctl list-timers` no master
- [x] **2.2** Identificar o motivo do sync ter parado (Nov/2025)
- [x] **2.3** Criar/restaurar CronJob de rclone sync MinIO → GDrive
  - Schedule sugerido: diário `0 3 * * *` (após longhorn backup-daily)
  - Escopo: `k8s-backups/backupstore/` e `k8s-backups/etcd/`
- [x] **2.4** Documentar em `components/backup/` como IaC

### 🟠 Fase 3 — Política de Retenção por Serviço

- [x] **3.1** Auditar Longhorn RecurringJobs: confirmar quais PVCs estão no grupo `default`
  - `kubectl get recurringjob -n longhorn-system -o yaml`
- [x] **3.2** Remover kubecost volumes do grupo `default` de backup (ou reduzir retain=3)
  - kubecost não é dado crítico; 1.3 GiB em backup é desperdício
- [x] **3.3** Avaliar coroot-data: verificar se 3.9 GiB é esperado com retain=7
  - Se >7 backups existem para coroot-data, forçar limpeza manual
- [x] **3.4** Definir política de retenção do bucket `nexus` no MinIO
  - Longhorn `backup-daily` não cobre nexus (10 GiB PVC — muito grande)
  - Nexus tem bucket próprio (4.3 GiB) — investigar o que está acumulando
- [x] **3.5** Remover VolumeSnapshots manuais obsoletos do postgres (dez/2025)
  - `kubectl delete volumesnapshot manual-20251201-090155 manual-20251201-091805 ... -n postgres`
- [x] **3.6** Documentar tabela de política de retenção por serviço em `docs/backup-policy.md`

### ✅ Fase 4 — Validação Final

- [x] **4.1** Confirmar tamanho total MinIO após limpeza (target: < 8 GiB em k8s-backups)
- [x] **4.2** Confirmar GDrive sync funcionando com conteúdo recente
- [x] **4.3** Confirmar etcd backup com arquivo no MinIO `k8s-backups/etcd/`
- [x] **4.4** Atualizar KANBAN.md com task concluída

### 🔧 Follow-up descoberto no re-audit de 2026-04-19

- [x] **1.8** Podar o prefixo `k8s-backups/etcd/` no MinIO para os quatro snapshots mais novos e remover artefatos legados `*.db.part`
- [x] **3.7** Planejar/validar cleanup retroativo dos `BackupVolume` órfãos e dos backups históricos de observability herdados do antigo `backup-daily`

---

## References

- `components/backup/longhorn-recurring-job.yaml` — `retain: 7`, grupo: default
- `components/backup/etcd-backup-cronjob.yaml` — depende de `/host-backup/etcd/latest_snapshot`
- `components/backup/snapshot-cronjob.yaml` — postgres VolumeSnapshots (retention=7, OK)
- `oci-k8s-cluster/kubeconfig_tunnel.yaml` — acesso kubectl local
