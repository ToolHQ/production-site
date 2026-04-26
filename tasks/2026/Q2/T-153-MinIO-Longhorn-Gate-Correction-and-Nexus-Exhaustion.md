# T-153: MinIO Longhorn Gate Correction and Nexus Exhaustion

- **Status**: Done
- **Priority**: High
- **Epic/Owner**: Infra
- **Estimation**: 3h
- **Closed**: 2026-04-25

## Context

Durante a execucao da [T-150](T-150-Master-Rootfs-Dependency-Reduction.md), o dataset do `MinIO` caiu
abaixo de `12Gi`, mas o primeiro preflight `longhorn-2` continuou falhando no live.

Era necessario fechar duas duvidas de forma versionada e definitiva:

- se ainda existia reclaim seguro relevante no `nexus/` via limpeza nativa do Nexus;
- se o gate da T-150 (`/data/minio <= 12Gi` + `storageAvailable`) realmente representava a capacidade
  Longhorn para um PVC `12Gi` com `2` replicas.

## Root Cause Confirmed

- o gate antigo era incompleto: `storageAvailable` bruto nao garante que um novo volume Longhorn seja
  agendavel com o replica count desejado;
- para este cluster, o numero que decide o preflight e o headroom Longhorn realmente agendavel por
  node: `((storageMaximum - storageReserved) * overprovision) - storageScheduled`;
- com `storage-over-provisioning-percentage=100` e `storage-minimal-available-percentage=10`, o estado
  live apos a limpeza deixou os workers aproximadamente assim:
  - `k8s-node-1`: `13.6Gi` agendaveis antes da replica local do preflight;
  - `k8s-node-2`: `7.6Gi` agendaveis;
  - `k8s-node-3`: `9.6Gi` agendaveis;
- isso permite a primeira replica de um volume `12Gi`, mas impede a segunda replica em qualquer outro
  worker; o resultado pratico foi volume `attaching` e pod `ContainerCreating` no staging do `MinIO`.

## Repo Hardening Versioned

- o helper [oci-k8s-cluster/lib/nexus_init.sh](../../../oci-k8s-cluster/lib/nexus_init.sh) ganhou o
  ciclo operacional faltante para cleanup nativo do Nexus:
  - `nexus_tasks_api_path`
  - `nexus_list_cleanup_tasks`
  - `nexus_get_task_json`
  - `nexus_run_task`
- o runbook [docs/nexus-cleanup-policy.md](../../../docs/nexus-cleanup-policy.md) passou a documentar o
  uso desses helpers e o fato de que o cleanup nativo foi executado sem reclaim;
- os artefatos de cutover do `MinIO` deixaram de tratar `storageAvailable` como gate suficiente.

## Live Execution Executed

- o source real foi medido em bytes: `/data/minio = 12675243344` bytes (`~11.80Gi`) e depois
  `/data/minio = 11066617457` bytes (`~10.31Gi`) com o reclaim assíncrono encerrado;
- o preflight versionado em
  [components/minio/minio-longhorn-preflight.yaml](../../../components/minio/minio-longhorn-preflight.yaml)
  foi aplicado no cluster e o PVC `minio-pvc-longhorn` ficou `Bound`;
- ao escalar o staging para `1`, o pod ficou em `ContainerCreating` e o volume correspondente ficou em
  `attaching`, com apenas uma replica real iniciada;
- para estabilizar o cluster, o deployment `minio-longhorn-staging` foi escalado de volta para `0`
  replicas, sem deletar o PVC/PV protegido;
- em paralelo, o cleanup nativo do Nexus foi executado via helpers versionados:
  - `repository.cleanup`: `OK`
  - `assetBlob.cleanup` `nuget`: `OK`
  - `assetBlob.cleanup` `maven2`: `OK`
  - `assetBlob.cleanup` `docker`: `OK`
  - `assetBlob.cleanup` `npm`: `OK`

## Closure Evidence

- `/data/minio/nexus` permaneceu em `4.6G` antes e depois das tasks do Nexus;
- `/data/minio` permaneceu em `11066617457` bytes antes e depois das tasks do Nexus (delta `0`);
- o `nexus_preview_npm_proxy_cleanup` seguiu retornando preview vazio para a policy
  `npm-proxy-unused-30d`;
- o preflight `12Gi` / `longhorn-2` foi provado como falso verde quando validado apenas com
  `storageAvailable`.

## Tasks

- [x] Medir o source do `MinIO` em bytes reais, sem confiar em `du -sh` arredondado.
- [x] Executar o preflight versionado do `MinIO` no live e capturar o ponto exato da falha.
- [x] Distinguir bloqueio de attach do kubelet vs bloqueio de envelope/scheduling do Longhorn.
- [x] Versionar helpers para listar, inspecionar e disparar tasks nativas do Nexus.
- [x] Executar `repository.cleanup` e todos os `assetBlob.cleanup` existentes e medir o delta real.
- [x] Corrigir o gate documentado da T-150 e do runbook do cutover.

## Residual Follow-up

- O `Nexus` deixa de ser candidato relevante para reclaim seguro nesta trilha; o bucket `nexus/` esta
  operacionalmente exaurido para esta investigacao.
- A [T-150](T-150-Master-Rootfs-Dependency-Reduction.md) permanece aberta, agora com o blocker correto:
  o alvo `12Gi` / `longhorn-2` nao cabe no envelope Longhorn atual.
- O proximo passo precisa ser uma decisao explicita entre:
  - reduzir ainda mais o dataset do `MinIO` ate caber em um envelope `2` replicas realmente agendavel;
  - ou mudar conscientemente a estrategia Longhorn (replica count / overprovision / storage dedicado)
    com IaC e risco documentados.

## References

- [T-150](T-150-Master-Rootfs-Dependency-Reduction.md)
- [components/minio/minio-longhorn-preflight.yaml](../../../components/minio/minio-longhorn-preflight.yaml)
- [components/minio/minio-longhorn-cutover.md](../../../components/minio/minio-longhorn-cutover.md)
- [docs/nexus-cleanup-policy.md](../../../docs/nexus-cleanup-policy.md)
- [oci-k8s-cluster/lib/nexus_init.sh](../../../oci-k8s-cluster/lib/nexus_init.sh)