# T-149: Master DiskPressure Recurrence Hardening

- **Status**: Done
- **Priority**: High
- **Epic/Owner**: Ops
- **Estimation**: 4h
- **Closed**: 2026-04-25

## Context
Em 2026-04-25 o cluster voltou a degradar no mesmo eixo que ja havia aparecido em T-124:
`k8s-master` entrou novamente em `DiskPressure=True`, o `ingress-nginx-controller`
ficou `0/1` e o namespace acumulou churn historico de pods `Evicted` / `Error` /
`ContainerStatusUnknown` no mesmo ReplicaSet.

Investigacao confirmada nesta execucao:

- o `ingress-nginx-controller` continua pinado no control plane via `hostNetwork: true`
	e `nodeSelector: k8s-master` em [components/ingress-nginx/deploy.yaml](../../../components/ingress-nginx/deploy.yaml);
- o master voltou a pressionar `ephemeral-storage`, com `DiskPressure=True` e eventos
	recorrentes `FreeDiskSpaceFailed` / `EvictionThresholdMet`;
- os dois maiores consumidores do rootfs continuavam sendo os mesmos de T-124:
	`/data/minio` (~18G, incluindo `k8s-backups`) e o cache rootless do BuildKit em
	`/home/ubuntu/.local/share/buildkit` (~14G);
- a lacuna de versionamento ficou explicita: o cleaner versionado em
	[oci-k8s-cluster/scripts/system_cleaner/clean_node.sh](../../../oci-k8s-cluster/scripts/system_cleaner/clean_node.sh)
	nao alcançava o BuildKit rootless do usuario `ubuntu` quando rodado como `root`, e o
	watchdog versionado em
	[oci-k8s-cluster/scripts/observability/cluster_health_check.sh](../../../oci-k8s-cluster/scripts/observability/cluster_health_check.sh)
	ainda nao promovia `DiskPressure` / `ephemeral-storage` a sinal primario.

## Update 2026-04-25 — Root cause and repo gaps

- T-124 ja tinha identificado o mesmo padrao estrutural: `MinIO` em `hostPath` no rootfs do
	control-plane e cache rootless do BuildKit fora do alcance do cleaner legado.
- A recorrencia aconteceu porque esse gap operacional nao tinha sido completamente codificado:
	o live cleanup anterior ainda dependia de uma acao manual extra para o BuildKit rootless.
- O kubelet do master entrou em loop de eviction mesmo depois da liberacao de espaco e so saiu
	definitivamente do estado apos o cleanup do cache rootless seguido de restart do kubelet.

## Update 2026-04-25 — Repo hardening versioned

- O cleaner versionado passou a:
	- podar explicitamente o BuildKit rootless do usuario `ubuntu` quando a execucao ocorre como `root`;
	- tolerar falta do socket live e limpar cache rootless stale offline quando o daemon nao estiver ativo;
	- truncar logs gigantes de `rsyslog` e descartar archives comprimidos antigos, cobrindo o caso real de `k8s-node-3`.
- O watchdog versionado passou a:
	- avaliar `DiskPressure`, `MemoryPressure` e `PIDPressure` como sinais de primeira classe;
	- destacar explicitamente quando o `ingress-nginx` esta pinado em um node com `DiskPressure`,
		incluindo o contexto de `hostNetwork` e `externalTrafficPolicy`.

## Update 2026-04-25 — Live remediation executed

- Master recovery:
	- cleaner atualizado sincronizado e executado no `k8s-master`;
	- prune do cache rootless do BuildKit e limpeza segura do rootfs;
	- restart do kubelet para encerrar o stale `DiskPressure` e o loop de eviction.
- Workload recovery:
	- restart forçado dos pods de `ingress-nginx-controller` e `minio-deployment`;
	- rollouts validados com ambos os deployments de volta a `1/1 Running` no master.
- Cluster-state follow-through:
	- `k8s-node-3` ainda mantinha o watchdog em vermelho por headroom de disco Longhorn;
	- diagnostico mostrou `Longhorn`, `containerd` e logs no mesmo rootfs, com `syslog` / `syslog.1`
		consumindo mais de 6G;
	- cleanup operacional recuperou o worker de `7.6G` livres / `85%` usados para `15G` livres /
		`71%` usados, e o Longhorn atualizou o `storageAvailable` para ~`14.1G`, removendo o estado critico.

## Closure Evidence

- `kubectl describe node k8s-master` passou a reportar `DiskPressure=False` com motivo
	`KubeletHasNoDiskPressure`.
- `kubectl -n ingress-nginx get deploy ingress-nginx-controller -o wide` validou `1/1`.
- `kubectl -n minio get deploy minio-deployment -o wide` validou `1/1`.
- `df -h /` no master estabilizou em `21G` livres (`59%` usado).
- `df -h /` no `k8s-node-3` estabilizou em `15G` livres (`71%` usado).
- O watchdog final saiu de vermelho para warning-only: sem `DiskPressure` em nenhum node e sem
	backlog vivo de `ingress-nginx` / `minio`.

## Tasks
- [x] Reproduzir a falha atual do `ingress-nginx-controller` e confirmar que o problema vivo era `DiskPressure` no master, nao image pull, probe ou quota.
- [x] Revisitar T-103, T-124, T-128 e T-130 para identificar o que foi corrigido e o que ficou como gap operacional.
- [x] Atualizar o cleaner versionado para podar explicitamente o BuildKit rootless do usuario `ubuntu` quando executado como `root`.
- [x] Atualizar o watchdog versionado para alertar `DiskPressure` / `ephemeral-storage` antes de o ingress voltar a cair.
- [x] Aplicar a remediacao segura no cluster live: prune do cache rootless, restart controlado dos deployments afetados e limpeza do estado terminal que mantinha ruído operacional.
- [x] Validar que `k8s-master` voltou para `DiskPressure=False` e que `ingress-nginx-controller` ficou `1/1 Running`.
- [x] Fechar a task com evidencias e explicitar o follow-up estrutural que continua fora do hotfix.

## Residual Follow-up

- A prevençao estrutural fica rastreada em [T-150](T-150-Master-Rootfs-Dependency-Reduction.md):
	reduzir a dependencia do rootfs do master para `MinIO` / `backupstore` e revisar o acoplamento
	do `ingress-nginx` ao control-plane.
- O cluster terminou esta execucao em warning-only por capacidade geral: CPU headroom apertado em
	parte dos nodes, restart churn recente no `kube-controller-manager` e disco Longhorn ainda abaixo
	do alvo ideal de `15G` em `k8s-node-2` / `k8s-node-3`. Esses pontos nao bloqueiam a recuperacao
	do incidente desta task.
