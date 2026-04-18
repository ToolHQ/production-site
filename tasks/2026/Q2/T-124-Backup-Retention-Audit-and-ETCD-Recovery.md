# T-124: Backup Retention Audit & ETCD Recovery

- **Status**: In Progress
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
- [/] **1.7** Restaurar novo run bem-sucedido após o master sair de `DiskPressure`

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

- [ ] **3.1** Auditar Longhorn RecurringJobs: confirmar quais PVCs estão no grupo `default`
  - `kubectl get recurringjob -n longhorn-system -o yaml`
- [ ] **3.2** Remover kubecost volumes do grupo `default` de backup (ou reduzir retain=3)
  - kubecost não é dado crítico; 1.3 GiB em backup é desperdício
- [ ] **3.3** Avaliar coroot-data: verificar se 3.9 GiB é esperado com retain=7
  - Se >7 backups existem para coroot-data, forçar limpeza manual
- [ ] **3.4** Definir política de retenção do bucket `nexus` no MinIO
  - Longhorn `backup-daily` não cobre nexus (10 GiB PVC — muito grande)
  - Nexus tem bucket próprio (4.3 GiB) — investigar o que está acumulando
- [ ] **3.5** Remover VolumeSnapshots manuais obsoletos do postgres (dez/2025)
  - `kubectl delete volumesnapshot manual-20251201-090155 manual-20251201-091805 ... -n postgres`
- [ ] **3.6** Documentar tabela de política de retenção por serviço em `docs/backup-policy.md`

### ✅ Fase 4 — Validação Final

- [ ] **4.1** Confirmar tamanho total MinIO após limpeza (target: < 8 GiB em k8s-backups)
- [ ] **4.2** Confirmar GDrive sync funcionando com conteúdo recente
- [ ] **4.3** Confirmar etcd backup com arquivo no MinIO `k8s-backups/etcd/`
- [ ] **4.4** Atualizar KANBAN.md com task concluída

---

## References

- `components/backup/longhorn-recurring-job.yaml` — `retain: 7`, grupo: default
- `components/backup/etcd-backup-cronjob.yaml` — depende de `/host-backup/etcd/latest_snapshot`
- `components/backup/snapshot-cronjob.yaml` — postgres VolumeSnapshots (retention=7, OK)
- `oci-k8s-cluster/kubeconfig_tunnel.yaml` — acesso kubectl local
