# T-150: Master Rootfs Dependency Reduction

- **Status**: Done
- **Priority**: High
- **Epic/Owner**: Infra
- **Estimation**: 1d

## Context
T-149 resolveu a recorrencia operacional do `DiskPressure` no `k8s-master`, mas a causa estrutural
permanece aberta e agora esta melhor delimitada com dados live:

- o `PersistentVolume` do `MinIO` continua em `hostPath: /data/minio`;
- `/data` e `/` no master sao o mesmo filesystem (`/dev/sda1`), portanto o bucket store pesa
  diretamente no rootfs do control-plane;
- o payload original sob `/data/minio` era de aproximadamente `18G`, mas a investigacao desta task ja o
  reduziu para `11066617457` bytes (`~10.31Gi`) sem ainda fechar o envelope Longhorn alvo;
- o `ingress-nginx-controller` continua pinado no `k8s-master` com `hostNetwork: true`,
  `externalTrafficPolicy: Local` e `nodeSelector` dedicado;
- o master nao participa do pool Longhorn; os `nodes.longhorn.io` ativos continuam sendo apenas
  `k8s-node-1`, `k8s-node-2` e `k8s-node-3`.

O incidente de 2026-04-25 deixou claro que nao basta endurecer cleaner/watchdog. Enquanto `MinIO`
e a borda HTTP dependerem do mesmo rootfs critico do control-plane, o cluster pode voltar para o
mesmo modo de falha.

## Validated Constraints

- `storageAvailable` bruto do Longhorn nao basta para decidir este cutover; o gate correto depende do
  envelope realmente agendavel em cada worker: `((storageMaximum - storageReserved) * overprovision) - storageScheduled`.
- No estado live validado apos a tentativa de preflight `12Gi` / `longhorn-2`, o headroom agendavel por
  worker ficou em aproximadamente:
  - `k8s-node-1`: `13.6Gi` antes da replica local do preflight;
  - `k8s-node-2`: `7.6Gi`;
  - `k8s-node-3`: `9.6Gi`.
- Com isso, o primeiro replica de um volume `12Gi` consegue nascer, mas a segunda replica nao cabe em
  nenhum outro worker sob `storage-over-provisioning-percentage=100` e
  `storage-minimal-available-percentage=10`.
- O resultado pratico e que um PVC `longhorn-2` de `12Gi` permanece bloqueado, mesmo depois de o
  dataset fonte ter ficado abaixo de `12Gi`.
- Mover `MinIO` de `hostPath` no master para `hostPath` em um worker apenas troca o nó em risco e
  nao remove a dependencia de rootfs.
- Como o master nao e um node Longhorn, nao existe cutover simples via um unico pod montando ao
  mesmo tempo o `hostPath` antigo e um PVC Longhorn novo.
- Alterar a borda do `ingress-nginx` sem validar o path externo e arriscado, porque a exposicao atual
  combina `hostNetwork`, `Service type=LoadBalancer` e `externalTrafficPolicy: Local`.

## Update 2026-04-25 — ETCD retention gate closed

- o primeiro bloqueio operacional para encolher o `MinIO` era a deriva de retencao do ETCD: o bucket
  `k8s-backups/etcd` tinha chegado a `22` snapshots logicos apesar da meta de `4`;
- a investigacao confirmou que o live tinha derivado da IaC versionada para CronJobs em
  `rclone/rclone:latest`, e o repo voltou a ser a fonte de verdade via
  [components/backup/etcd-backup-cronjob.yaml](../../../components/backup/etcd-backup-cronjob.yaml);
- os CronJobs live foram restaurados com `kubectl apply --server-side --force-conflicts`, e os jobs
  `etcd-backup-validation` e `etcd-backup-prune-validation` fecharam `Complete 1/1`;
- depois da convergencia, `/data/minio/k8s-backups/etcd` ficou em `4` snapshots logicos `etcd-*.db`
  e `~1019M`, enquanto `/var/backup/etcd` ficou em `4` snapshots `.db` + `latest_snapshot`;
- com isso, a retençao do ETCD deixou de ser o bloqueio principal desta task. O restante da reducao do
  dataset do `MinIO` agora depende de revisar o footprint de `backupstore`, payload do `Nexus` e o
  volume agregado ainda hospedado no rootfs do master.

## Update 2026-04-25 — backupstore/Nexus exhausted, Longhorn gate corrected

- a retencao observability do Longhorn foi reduzida de `3` para `2` e depois para `1`, deixando os `5`
  volumes do grupo com exatamente `1` backup cada e reduzindo `backupstore` de forma material;
- o payload fonte do `MinIO` convergiu para `12675243344` bytes (`~11.80Gi`) e depois para
  `11066617457` bytes (`~10.31Gi`) conforme o reclaim assíncrono terminou;
- com o source abaixo de `12Gi`, o preflight versionado em
  [components/minio/minio-longhorn-preflight.yaml](../../../components/minio/minio-longhorn-preflight.yaml)
  foi aplicado no live e o PVC `minio-pvc-longhorn` ficou `Bound`;
- a validacao falhou no passo seguinte: o pod `minio-longhorn-staging` ficou em `ContainerCreating` e o
  volume Longhorn correspondente ficou preso em `attaching`, com apenas uma replica efetivamente
  iniciada e a segunda sem envelope de scheduling;
- o bloqueio nao era mais o `Nexus`: os tasks nativos `repository.cleanup` e todos os
  `assetBlob.cleanup` existentes foram executados via helpers versionados e fecharam `OK`, mas com delta
  medido de `0` bytes em `/data/minio`;
- a conclusao nova desta task e que o gate antigo (`/data/minio <= 12Gi` + `storageAvailable`) era um
  falso verde para o alvo `12Gi` / `longhorn-2`.

## Decision Matrix

### Option A — mover `MinIO` para outro `hostPath` local

- **Status**: Rejeitada
- **Motivo**: nao remove o problema de rootfs e nenhum worker tem folga confortavel para receber os
  ~`18G` atuais do dataset.

### Option B — mover `MinIO` para PVC Longhorn com replicas controladas

- **Status**: Caminho preferido, mas bloqueado no estado atual
- **Motivo**: usa stack ja operacional no cluster, tira o payload do rootfs do master e permite que o
  workload rode em worker;
- **Risco conhecido**: `MinIO` continua sendo backend de `Longhorn backupstore` e blob store do
  `Nexus`, entao a topologia passa a depender do Longhorn para servir esses buckets;
- **Mitigacao**: manter `GDrive` como copia off-site canonica, limitar replicas do PVC do `MinIO` para
  `2` por economia e so aplicar o cutover depois que o dataset couber no envelope real agendavel dos
  workers; `storageAvailable` isolado nao serve mais como gate.

### Option C — novo storage dedicado fora do rootfs atual

- **Status**: Desejavel, mas fora deste hotfix
- **Motivo**: seria a melhor solucao estrutural, mas depende de recurso/provisionamento que nao esta
  disponivel hoje dentro da politica de zero custo variavel.

## Chosen Direction

### Phase 1 — MinIO off the master rootfs

Objetivo: migrar o dataset do `MinIO` para um PVC Longhorn com footprint controlado e agendar o pod
em worker, sem continuar usando `/data/minio` como backend live.

Plano tecnico:

1. Reduzir ao minimo o payload do bucket store antes do cutover, preservando as regras de
   [docs/backup-policy.md](../../../docs/backup-policy.md).
2. So avancar quando o dataset do `MinIO` couber no envelope Longhorn realmente agendavel; isso exige
  validar bytes reais do source e o headroom Longhorn por replica, nao apenas `storageAvailable`.
3. Com o estado live atual, o alvo `12Gi` / `longhorn-2` continua bloqueado porque a segunda replica
  nao cabe em nenhum worker alem do node que recebe a replica local inicial.
4. Criar um PVC Longhorn dedicado ao `MinIO`, com replicas limitadas a `2`, somente apos o gate de
  capacidade estar verde.
5. Subir um helper pod temporario em worker com o PVC novo montado.
6. Fazer a copia do dataset por stream a partir do master (`/data/minio`) para o PVC novo, porque o
   master nao consegue montar volumes Longhorn diretamente.
7. Trocar o deployment do `MinIO` para usar o PVC novo e remover o pinning ao `k8s-master`.
8. Preservar rollback explicito mantendo o dataset antigo intocado ate a validacao final.

### Phase 2 — decouple ingress from the master

Objetivo: remover o `nodeSelector: k8s-master` do `ingress-nginx-controller` sem quebrar a borda.

Plano tecnico:

1. Validar o path externo real usado hoje para `*.dnor.io` e os listeners de `80/443` antes de
   qualquer repin live.
2. Se a borda nao depender estritamente do IP publico do master, migrar para deployment com
   replicas >= `2`, sem pinning ao master e com preferencia por workers.
3. Se a borda depender do master hoje, abrir follow-up especifico de edge before applying the change,
   em vez de remover o pinning cegamente.

Resultado da validacao live em 2026-04-25:

- o `k8s-master` continua sendo o unico node ouvindo `80/443` do ingress;
- o deployment segue com `hostNetwork: true`, `replicas: 1` e `nodeSelector: k8s-master`;
- o service continua `LoadBalancer` com `externalTrafficPolicy: Local`.

Com isso, a remocao do pinning do ingress sai desta task e passa a ser rastreada em
[T-151](T-151-Ingress-Edge-Decoupling-from-Master.md).

## Tasks
- [x] Confirmar com evidencias live que `MinIO` ainda usa `hostPath /data/minio` no mesmo filesystem
      do rootfs do master.
- [x] Confirmar com evidencias live que `ingress-nginx-controller` ainda esta hard-pinned ao
      `k8s-master`.
- [x] Fechar a matriz de decisao de storage e rejeitar explicitamente a troca simples para outro
      `hostPath` local.
- [x] Definir o envelope de capacidade do PVC Longhorn alvo do `MinIO` (replicas, node placement,
      rollback e risco para `Nexus` / `backupstore`).
- [x] Versionar a mudanca de IaC do `MinIO` como plano de cutover nao aplicado automaticamente:
      PVC novo, helper pod de staging e deployment alvo em worker.
- [x] Desenhar o procedimento operacional de copia do dataset do master para o PVC Longhorn com
      validacao e rollback.
- [x] Reconvergir a retencao do ETCD entre repo e cluster live, validando `4` snapshots locais e `4`
  snapshots logicos remotos como novo baseline estavel.
- [x] Validar o gate fonte em bytes reais e provar no live que o preflight `12Gi` / `longhorn-2`
  continua bloqueado por envelope Longhorn, nao mais por ETCD/backupstore/Nexus.
- [x] Reduzir o restante do dataset do `MinIO` para caber no envelope Longhorn validado. Cutover executado
  com sucesso via Job `minio-local-copy`; deployment do MinIO rodando em worker com `minio-pvc-longhorn`.
  Dataset legado em `/data/minio` arquivado em `minio_legacy_backup.tar.gz` e removido via Job
  `minio-legacy-cleanup` em 2026-04-26.
- [x] Validar a topologia de borda atual do `ingress-nginx` e decidir se a remocao do pinning ao
  master pode entrar nesta task ou precisa de follow-up separado.
- [x] Atualizar a task com o comando/plano exato de execucao live e os gates de aprovacao, porque a
      mudanca envolve recursos protegidos (`PV`, `PVC`, deployment critico e storage stateful).

## Safety Gates

- Nao deletar `PV`, `PVC`, namespace `minio` nem o deployment atual sem aprovacao explicita.
- O dataset legado em `/data/minio` so pode ser removido depois de validacao funcional do novo backend
  e checkpoint explicito de rollback.
- A mudanca do `ingress-nginx` so pode sair do repo para o cluster depois da validacao do path externo
  atual, porque `hostNetwork + LoadBalancer + externalTrafficPolicy: Local` nao permite suposicao.

## Definition of Done

- Existe um plano versionado e executavel para tirar o `MinIO` do rootfs do master.
- A alternativa escolhida nao depende de suposicoes falsas sobre `storageAvailable` ou capacidade atual
  dos workers.
- O cutover do `MinIO` possui rollback explicito.
- A estrategia do `ingress-nginx` esta decidida com base em validacao do path de borda, nao por
  tentativa e erro.

## Objective
Remover o rootfs do master como ponto unico de falha para backup object storage e entrada HTTP do
cluster.

## References
- [T-149](T-149-Master-DiskPressure-Recurrence-Hardening.md)
- [components/minio/minio-resources.yaml](../../../components/minio/minio-resources.yaml)
- [components/ingress-nginx/deploy.yaml](../../../components/ingress-nginx/deploy.yaml)
- [docs/backup-policy.md](../../../docs/backup-policy.md)
- [oci-k8s-cluster/scripts/system_cleaner/clean_node.sh](../../../oci-k8s-cluster/scripts/system_cleaner/clean_node.sh)
- [components/minio/minio-longhorn-preflight.yaml](../../../components/minio/minio-longhorn-preflight.yaml)
- [components/minio/minio-longhorn-target.yaml](../../../components/minio/minio-longhorn-target.yaml)
- [components/minio/minio-longhorn-cutover.md](../../../components/minio/minio-longhorn-cutover.md)
- [T-151](T-151-Ingress-Edge-Decoupling-from-Master.md)
- [T-152](T-152-ETCD-Backup-Retention-Drift-Convergence.md)
- [T-153](T-153-MinIO-Longhorn-Gate-Correction-and-Nexus-Exhaustion.md)
