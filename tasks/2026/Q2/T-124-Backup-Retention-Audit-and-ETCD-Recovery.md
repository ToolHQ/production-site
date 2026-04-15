# T-124: Backup Retention Audit & ETCD Recovery

- **Status**: Backlog
- **Priority**: 🚨 Critical
- **Owner**: Infra
- **Est.**: 3h
- **Created**: 2026-04-15

---

## Context

### Situação atual (snapshot 2026-04-15)

Análise executiva do storage de backup revelou problemas críticos e oportunidades de otimização:

#### 🗄️ MinIO (in-cluster) — 16.3 GiB total

| Bucket         | Tamanho | Objetos |
|----------------|---------|---------|
| `k8s-backups`  | 12 GiB  | 11,222  |
| `nexus`        | 4.3 GiB | 3,908   |

**Top consumidores em `k8s-backups/backupstore/volumes/`:**

| Serviço                    | Tamanho  | Objetos | PVC                    |
|----------------------------|----------|---------|------------------------|
| coroot-data                | **3.9 GiB** | 3,633 | pvc-efbe8d2c (coroot)  |
| kubecost-prometheus-server | **1.2 GiB** | 980   | pvc-76755523 (kubecost)|
| nexus-pvc                  | 112 MiB  | 288     | pvc-229e3768 (nexus)   |
| kubecost-cost-analyzer     | 74 MiB   | 436     | pvc-3a209369 (kubecost)|
| postgres-data-postgres-1   | 14 MiB   | 89      | pvc-901a3108 (postgres)|
| postgres-data-postgres-0   | 12 MiB   | 75      | pvc-fd9d35d1 (postgres)|
| coroot-clickhouse          | 304 KiB  | 26      | pvc-23ab203e (coroot)  |

#### ☁️ Google Drive (rclone)

| Pasta                          | Status        | Última sync  |
|-------------------------------|---------------|--------------|
| `k8s-backups/backupstore/`     | Mirror do MinIO | 2025-11-27 |
| `k8s-backups/etcd/`            | 🔴 VAZIO       | 2026-01-02  |

#### CronJobs de backup configurados

| Job                    | Schedule    | Última execução | Status  |
|------------------------|-------------|-----------------|---------|
| `longhorn backup-daily` | `0 1 * * *` | 2026-04-15 01:00 | ✅ OK |
| `etcd-backup`          | `0 */6 * * *` | **2026-02-21** | 🔴 QUEBRADO |
| `postgres-auto-snapshot` | `0 */6 * * *` | correndo | ✅ OK |

---

### 🚨 Problemas Críticos

1. **ETCD backup completamente quebrado há 53 dias**
   - Último run: 21/02/2026
   - `k8s-backups/etcd/` no MinIO está **VAZIO**
   - `/host-backup/etcd/` não existe em nenhum nó
   - O job depende deste path para ler o snapshot e fazer upload
   - **Risco**: perda total do control plane sem backup recuperável
   - Diagnóstico necessário: o job está falhando silenciosamente? O snapshot etcd deixou de ser gerado no host?

2. **GDrive sync desatualizado (~4 meses)**
   - `backupstore/` no GDrive não é atualizado desde Nov/2025
   - Não há rclone cronjob visível no cluster
   - Off-site backup essencialmente inexistente

---

### 💡 Oportunidades de Otimização

- **coroot-data (3.9 GiB)**: dados de observabilidade não precisam de retenção > 7 backups. Verificar se o `backup-daily` com `retain: 7` está sendo respeitado ou se volumes órfãos não são limpos.
- **kubecost volumes (1.3 GiB)**: kubecost é ferramenta de custo monitoring, não dado crítico. Avaliar reduzir retenção ou excluir do grupo `default` do Longhorn backup.
- **nexus bucket (4.3 GiB)**: sem política de retenção visível. Artifacts antigos acumulando.
- **Postgres snapshots**: 8 VolumeSnapshots existem (retention=7), funcionando corretamente. Porém há snapshots manuais de dez/2025 que podem ser removidos.

---

## Tasks

### 🔴 Fase 1 — ETCD Recovery (Crítico — fazer PRIMEIRO)

- [ ] **1.1** Investigar por que `/host-backup/etcd/` não existe nos nós
  - Verificar se há systemd timer/script que gera o snapshot etcd no host
  - Checar se o path foi montado no `etcd-backup` CronJob (hostPath volume)
- [ ] **1.2** Verificar logs do `etcd-backup` job no kube-system
  - `kubectl logs -n kube-system -l job-name=etcd-backup` dos últimos runs
  - Identificar o erro exato
- [ ] **1.3** Reparar o pipeline etcd → MinIO
  - Opção A: restaurar script de snapshot no host (se era externo ao cronjob)
  - Opção B: refatorar o cronjob para usar `etcdctl snapshot save` diretamente
- [ ] **1.4** Validar: executar job manualmente e confirmar upload no MinIO
- [ ] **1.5** Atualizar `components/backup/etcd-backup-cronjob.yaml` com a correção

### 🟡 Fase 2 — GDrive Sync Recovery

- [ ] **2.1** Verificar se existe rclone cronjob/systemd timer ativo no cluster ou no master
  - `kubectl get cronjob -A | grep rclone`
  - `systemctl list-timers` no master
- [ ] **2.2** Identificar o motivo do sync ter parado (Nov/2025)
- [ ] **2.3** Criar/restaurar CronJob de rclone sync MinIO → GDrive
  - Schedule sugerido: diário `0 3 * * *` (após longhorn backup-daily)
  - Escopo: `k8s-backups/backupstore/` e `k8s-backups/etcd/`
- [ ] **2.4** Documentar em `components/backup/` como IaC

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
