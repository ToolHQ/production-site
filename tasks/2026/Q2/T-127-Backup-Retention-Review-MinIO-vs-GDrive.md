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

4. **ETCD continua sem acervo armazenado**
   - O problema correto nao e "falha silenciosa"
   - O CronJob `etcd-backup` esta com `spec.suspend=true`
   - Resultado: `k8s-backups/etcd/` vazio em ambas as camadas

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

### Entregas aplicadas nesta rodada

- `backup-observability-daily` foi criado no cluster com `retain: 3` para
  observabilidade regeneravel.
- A policy por PVC foi aplicada: `coroot` e `kubecost` sairam do grupo `default` e foram
  movidos para `observability`.
- O sync para GDrive foi trocado de mirror destrutivo para archive append-only no
  `backupstore`, mantendo `etcd` com retencao separada.
- Units systemd + instalador do `gdrive-sync` foram versionados em Git e instalados no
  master; proximo disparo agendado para `03:30 UTC`.

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
  - [ ] Reativar / corrigir o pipeline do `etcd-backup`
  - [ ] Garantir que MinIO e GDrive passem a receber arquivos de ETCD
  - [ ] Definir retencao separada para control plane backups

- [ ] Entregar recomendacao final
  - [x] Tabela final: volume -> criticidade -> destino -> retencao MinIO -> retencao GDrive
  - [ ] Plano de limpeza segura do backlog atual
  - [ ] Estimativa de reducao de storage sem comprometer recoverability

---

## References

- `components/backup/longhorn-recurring-job.yaml`
- `components/backup/etcd-backup-cronjob.yaml`
- `tasks/2026/Q2/T-124-Backup-Retention-Audit-and-ETCD-Recovery.md`
