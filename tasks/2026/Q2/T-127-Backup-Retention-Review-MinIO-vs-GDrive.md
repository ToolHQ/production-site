# T-127: Backup Retention Review — MinIO vs GDrive

- **Status**: In Progress
- **Priority**: 🚨 Critical
- **Owner**: Infra
- **Est.**: 3h
- **Created**: 2026-04-15

---

## Context

A revisao inicial de backup retention mostrou que a premissa anterior estava errada: o
Google Drive **nao** esta servindo hoje como camada historica mais longa; ele esta quase
espelhando o mesmo acervo do MinIO.

### Estado corrigido observado em 2026-04-15

#### Capacidade / acervo

| Camada | Escopo | Estado atual |
| --- | --- | --- |
| MinIO | `/data/k8s-backups` | ~14.64 GiB em disco |
| GDrive | `gdrive:k8s-backups` | 22,741 objetos / 12.45 GiB |
| MinIO | `nexus` | ~4.33 GiB (nao e backup Longhorn) |
| ETCD | `k8s-backups/etcd` | vazio em MinIO e GDrive |

#### Janela observada

- Janela confirmada no inventario Longhorn: **2025-12-14 -> 2026-04-15**
- Janela atual dos volumes ativos mais pesados: **~2026-02-02/03 -> 2026-04-15**
- GDrive nao mostra uma janela mais longa que MinIO; ele replica praticamente os mesmos
  objetos do `backupstore`

#### Configuracao declarada vs estado real

`longhorn-system/RecurringJob backup-daily`:

- `task: backup`
- `cron: 0 1 * * *`
- `retain: 7`

Mesmo assim, volumes atuais importantes estao acima disso:

| Volume atual | MinIO | GDrive | Observacao |
| --- | ---: | ---: | --- |
| `coroot-prometheus-server` | 19 backups | 20 entradas | maior consumidor |
| `coroot-data` | 17 backups | 18 entradas | acima do esperado |
| `kubecost-prometheus-server` | 20 backups | 21 entradas | acima do esperado |
| `nexus-pvc` | 19 backups | 20 entradas | acima do esperado |

### Principais achados

1. **Nao existe hoje politica tiered de retencao**
   - O esperado seria: MinIO = curto prazo, GDrive = curto + historico
   - O observado e: GDrive ~= espelho quase 1:1 do MinIO

2. **Retencao real diverge da declarada**
   - A politica ativa declara `retain: 7`
   - O bucket atual guarda ~17-20 backups por volume em varios casos

3. **Coroot esta carregando historico demais**
   - `coroot-prometheus-server` e o maior consumidor do backupstore
   - `coroot-data` tambem esta acima do racional para observabilidade
   - Em cluster de 1 vCPU / 6 GB por no, isso nao parece justificavel

4. **ETCD continua sem pipeline saudavel**
   - O problema nao e ausencia total de path local
   - O CronJob `etcd-backup` ficou suspenso por longo periodo
   - O acervo local tambem ficou inconsistente, com `latest_snapshot` parado em
     `2026-02-21` e dezenas de arquivos `.part` de `2026-02-02`

### Hipoteses a validar

- O Longhorn pode nao estar limpando backups antigos de volumes que mudaram de grupo /
  politica ao longo do tempo
- O `retain: 7` pode estar valendo apenas para novos ciclos e nao reconciliando backlog
  antigo
- O GDrive sync pode ser um mirror simples do bucket inteiro, sem qualquer logica de
  tiering ou lifecycle
- Os volumes do Coroot podem ter sido mantidos por excesso de cautela pos-incidente, mas
  sem revisao posterior de storage policy

## Audit update (2026-04-15)

### Achados validados em cluster

- O offsite sync nao roda em Kubernetes. Ele vive no master como `gdrive-sync.service` +
  `gdrive-sync.timer` em systemd.
- O timer estava `enabled`, com ultimo run em `2026-04-15 00:00 UTC`.
- O fluxo atual usava `rclone sync` contra o bucket inteiro `k8s-backups`, portanto o
  GDrive se comportava como mirror quase direto do MinIO, sem tiering real.
- O log de sync mostrou `directory not found` durante a copia do `backupstore`, causado
  por mutacao concorrente do Longhorn; o retry seguinte concluiu. Isso reforca que mirror
  destrutivo nao e uma estrategia segura para esse layout.
- O `longhorn-system` hoje tem apenas dois recurring jobs: `backup-daily` e
  `maintenance-cleanup`.
- Os volumes ativos de `nexus`, `coroot` e `kubecost` estavam em `7` backups, coerentes
  com `retain: 7`.
- O excesso historico veio de duas fontes distintas:
  - `BackupVolume` herdados de geracoes antigas de PVC (principalmente dez/2025 -> jan/2026);
  - `postgres-auto-snapshot`, cujos `VolumeSnapshotContents` usam handle `bak://...` e
    geram backups adicionais do Longhorn a cada 6 horas para `postgres-data-postgres-0`.
- O `etcd-backup` nao estava apenas suspenso: um run manual em `2026-04-15` confirmou que
  o init container ainda cria snapshot valido (`etcd-20260415-161757.db`), mas o upload
  falha por `ImagePullBackOff`.
- A causa do `ImagePullBackOff` e drift no cluster: o container `s3-upload` ativo tenta
  puxar `registry.local:31444/repository/docker-repo/etcd:3.5.17-debian-12-r0` sem
  credencial, enquanto o manifesto versionado no repo usa `minio/mc`.
- A segunda causa validada foi estrutural: o CronJob estava montando `/data/minio/k8s-backups`
  como `hostPath` de staging. Na pratica, o snapshot era salvo direto no backend filesystem do
  bucket e depois o `mc cp` tentava enviar o mesmo objeto via S3, produzindo `AccessDenied`.
- O staging correto precisa ficar fora do datadir do MinIO (ajuste aplicado no manifesto para
  `/var/backup`).
- Com o staging movido para `/var/backup`, um run manual (`etcd-backup-manual-5`) concluiu com
  sucesso em `2026-04-15`, gerando `etcd-20260415-164937.db` e enviando `254.52 MiB` ao bucket
  `k8s-backups/etcd/`.
- Em `2026-04-16`, o `gdrive-sync` foi corrigido para copiar ETCD a partir de
  `/var/backup/etcd` em vez de ler o datadir do MinIO; o snapshot
  `etcd-20260416-000005.db` foi validado no GDrive com `266883104` bytes.
- Restam artefatos remotos legados criados pelo fluxo antigo (`*.db/` com `xl.meta`, alem de
  `perm-check-*` e `test-write.txt`), que precisam de limpeza dirigida no GDrive antes de
  reutilizar alguns nomes historicos.

### Cleanup candidate set (2026-04-18)

- Diretorios remotos invalidos em `gdrive:k8s-backups/etcd/`:
  - `etcd-20260112-131425.db/`
  - `etcd-20260112-131444.db/`
  - `etcd-20260415-164937.db/`
  - `etcd-20260415-180005.db/`
  - `etcd-20260416-000005.db/`
  - `etcd-20260416-060005.db/`
  - `perm-check-1776270602.txt/`
  - `test-write.txt/`
- Arquivo auxiliar remoto sem valor de restore:
  - `latest_snapshot`
- Colisao remota de nome a deduplicar apos o purge:
  - `etcd-20260416-000005.db` (2 copias validas de `266883104` bytes)
- Impacto estimado do cleanup remoto no GDrive ETCD:
  - remoto atual: `81` objetos / `3.480 GiB`
  - purge dos diretorios legados + artefatos de teste: `~1.24 GiB`
  - dedupe adicional: `266883104` bytes (`254.52 MiB`)
  - `latest_snapshot`: `24` bytes
- Backlog legado confirmado no Longhorn backupstore:
  - `11` `BackupVolume` historicos sem volume vivo correspondente
  - `88` backups herdados de geracoes antigas de PVC
  - `~5.57 GiB` ainda ocupados no target `default`
  - maiores candidatos: geracoes antigas de `elasticsearch-data-oci-logs-es-default-{0,1}` e
    `kubecost-prometheus-server`
- Script preparado para a limpeza: `oci-k8s-cluster/scripts/cloud_ops/cleanup_gdrive_etcd_legacy.sh`

### Entregas aplicadas nesta rodada

- `backup-observability-daily` foi criado no cluster com `retain: 3` para
  observabilidade regeneravel.
- A policy por PVC foi aplicada: `coroot` e `kubecost` sairam do grupo `default` e foram
  movidos para `observability`.
- O sync para GDrive foi trocado de mirror destrutivo para archive append-only no
  `backupstore`, mantendo `etcd` com retencao separada.
- Units systemd + instalador do `gdrive-sync` foram versionados em Git e instalados no
  master; proximo disparo agendado para `03:30 UTC`.
- O script no master foi atualizado para usar `/var/backup/etcd` como fonte offsite de ETCD.

---

## Tasks

- [x] Levantar a politica real de retention por camada
  - [x] Identificar como o GDrive esta sendo sincronizado hoje
  - [x] Confirmar se existe qualquer mecanismo de tiering/lifecycle entre MinIO e GDrive
  - [x] Documentar a janela efetiva de MinIO vs GDrive por volume relevante

- [x] Explicar por que o `retain: 7` nao esta se refletindo no bucket
  - [x] Auditar `RecurringJob`, `BackupVolume` e `Backup` do Longhorn
  - [x] Verificar backlog herdado de politicas antigas / grupos antigos
  - [x] Confirmar se cleanup automatico esta deixando lixo historico no backupstore

- [x] Revisar os volumes de observabilidade
  - [x] `coroot-prometheus-server`
  - [x] `coroot-data`
  - [x] Validar se faz sentido manter backup destes dados no mesmo nivel de retencao do
        postgres / nexus
  - [x] Propor politica alvo para observabilidade com foco em "Stability First"

- [x] Revisar volumes de menor criticidade
  - [x] `kubecost-prometheus-server`
  - [x] `kubecost-cost-analyzer`
  - [x] Definir se devem sair do backup-daily ou ter retencao menor

- [x] Corrigir a estrategia entre MinIO e GDrive
  - [x] Definir objetivo oficial:
        - MinIO = curto prazo
        - GDrive = historico estendido
  - [x] Propor como materializar isso sem custo variavel
  - [x] Especificar criterio de corte (dias / quantidade / classes de volume)

- [ ] Revisar ETCD retention em paralelo
  - [x] Reativar / corrigir o pipeline do `etcd-backup`
        - `spec.suspend` reaberto no manifesto versionado
        - drift do container de upload identificado no cluster
        - colisao entre staging local e datadir do MinIO identificada
  - [x] Garantir que MinIO e GDrive passem a receber arquivos de ETCD
    - MinIO validado com snapshots completos de `2026-04-15` e `2026-04-16`
    - GDrive validado com `etcd-20260416-000005.db` em `266883104` bytes
    - restam apenas artefatos legados do fluxo antigo para cleanup remoto
  - [x] Definir retencao separada para control plane backups
    - staging local: `7d`
    - GDrive: `30d`

- [ ] Entregar recomendacao final
  - [x] Tabela final: volume -> criticidade -> destino -> retencao MinIO -> retencao GDrive
  - [/] Plano de limpeza segura do backlog atual
        - candidate set remoto do GDrive isolado
        - utilitario dry-run preparado para purge + dedupe
    - backlog legado do Longhorn quantificado
    - impacto do purge remoto do GDrive quantificado
  - [x] Estimativa de reducao de storage sem comprometer recoverability

---

## References

- `components/backup/longhorn-recurring-job.yaml`
- `components/backup/etcd-backup-cronjob.yaml`
- `tasks/2026/Q2/T-124-Backup-Retention-Audit-and-ETCD-Recovery.md`
