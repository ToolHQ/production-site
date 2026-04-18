# T-128: Cluster Yellow-State Cleanup

- **Status**: Done
- **Priority**: 🔼 High
- **Owner**: Infra
- **Est.**: 4h
- **Created**: 2026-04-18

---

## Context

Snapshot validado em 2026-04-18 após a recuperação do incidente de `DiskPressure` no `k8s-master`:

- Todos os nós estão `Ready` e sem `MemoryPressure` / `DiskPressure` / `PIDPressure`.
- `ingress-nginx-controller`, `minio-deployment` e `kubecost-prometheus-server` voltaram para `1/1`.
- O cluster está operacionalmente saudável, mas ainda não está totalmente verde por três resíduos de saúde operacional.

### Residual 1 — kube-apiserver `0/1 Ready` com API viva

- O pod `kube-apiserver-k8s-master` segue aparecendo como `0/1 Running`.
- O endpoint `kubectl get --raw='/readyz?verbose'` responde `readyz check passed`, então a API está servindo.
- O pod teve `Last State: OOMKilled` recentemente e o `startupProbe` observado sugere wiring incorreto (`probe-port` na URL), o que indica possível problema de probe e, possivelmente, pressão de memória no control plane.
- Precisamos classificar corretamente se isso é bug de probe, problema de sizing, ou ambos.

### Residual 2 — `cert-manager` repair job bloqueado por quota

- O job `chain-repair-29600760` permanece sem progresso há dias.
- O namespace `cert-manager` está com `limits.memory=1Gi` totalmente consumido pelos pods steady-state.
- O repair job não consegue criar pod porque a quota não deixa reservar nem mais `64Mi` de limite.
- O plano precisa corrigir isso sem afrouxar a quota de forma irresponsável.

### Residual 3 — warnings de snapshot em `postgres` / Longhorn

- A cauda recente de warning events ainda mostra ruído relacionado a snapshots do `postgres` e Longhorn.
- Precisamos separar warning histórico de falha viva e validar um ciclo novo, limpo e reproduzível.
- Se o problema estiver só no report/watchdog, o ajuste correto é na classificação do evento; se for falha real, a correção deve ir na automação de snapshot.

### Objetivo

Levar o cluster de “🟡 operacionalmente saudável” para “🟢 validado”, eliminando ou classificando formalmente esses três resíduos sem introduzir churn no control plane.

### Update 2026-04-18 — Resultado executado

- **kube-apiserver**: a causa real do `0/1` era o `startupProbe` inválido com `port: probe-port` no static manifest do master. O fix exigiu duas etapas: trocar o probe para `6443` e remover um backup do manifesto que havia ficado indevidamente dentro de `/etc/kubernetes/manifests`, fazendo o kubelet continuar vendo um manifesto concorrente. Estado final: `kube-apiserver-k8s-master 1/1 Running` e `readyz check passed`.
- **cert-manager**: o namespace estava no teto exato de `limits.memory=1Gi`; um bump cirúrgico para `1280Mi` destravou o `chain-repair-29600760`, que concluiu com sucesso, e também permitiu a janela seguinte (`chain-repair-29607960`) completar normalmente.
- **postgres snapshots**: o warning não era mais ruído puro; havia falha real no CronJob sob retry. O pipeline foi endurecido para usar nome determinístico por Job, `restartPolicy: Never`, `backoffLimit: 1`, timeout maior de readiness e criação via `printf` em vez de here-doc frágil. A execução manual de validação completou com sucesso e a retenção voltou para `7` snapshots automatizados.
- **Observação de escopo**: o watchdog ainda acusa falsos positivos/pendências antigas em `VolumeAttachment` e pressão estrutural de CPU por nó; isso permanece fora do escopo da T-128 e continua endereçado por T-102/T-103/T-104.

---

## Tasks

### Fase 1 — kube-apiserver readiness/probe

- [x] Reproduzir o estado atual com evidências: `describe`, probes, `readyz`, `livez`, restart count e `Last State`.
- [x] Inspecionar o manifesto estático do kube-apiserver no master e comparar probe/host/port com o comportamento real.
- [x] Validar se há relação entre o `OOMKilled` recente e o footprint atual de memória do apiserver.
- [x] Aplicar a menor correção segura possível e confirmar `1/1 Ready` sem regressão na API.

### Fase 2 — destravar repair job do cert-manager

- [x] Inspecionar spec do `chain-repair-29600760`, recursos pedidos e uso atual da `cert-manager-quota`.
- [x] Escolher a correção de menor risco entre: ajuste mínimo de quota, ajuste do footprint do job, ou descarte seguro do job caso esteja obsoleto.
- [x] Validar que os pods principais do `cert-manager` continuam saudáveis durante a correção.
- [x] Confirmar que o repair job concluiu ou foi encerrado com justificativa documentada.

### Fase 3 — warnings de snapshot do postgres/Longhorn

- [x] Identificar quais controladores/jobs/CRs estão emitindo os warnings recentes.
- [x] Separar warning histórico de erro ativo usando timestamps, Jobs, VolumeSnapshots e estado do volume Longhorn.
- [x] Executar ou observar um ciclo novo de snapshot do `postgres` e validar o resultado fim a fim.
- [x] Corrigir a origem do warning ou documentar/ajustar a lógica de classificação para evitar falso positivo recorrente.

### Fase 4 — validação final

- [x] Confirmar que não há warning ativo novo para kube-apiserver, cert-manager repair e snapshot do postgres.
- [x] Confirmar que o apiserver está `1/1 Ready` ou deixar uma exceção explícita, comprovada e aceita.
- [x] Confirmar que não existe workload bloqueado no namespace `cert-manager` por quota remanescente.
- [x] Atualizar `tasks/KANBAN.md` e referenciar follow-ups estruturais, se surgirem.

---

## Acceptance Criteria

- [x] `kube-apiserver-k8s-master` deixa de aparecer como residual amarelo sem afetar disponibilidade do API server.
- [x] `cert-manager` não fica mais com repair job preso por quota de memória.
- [x] Um ciclo fresco de snapshot do `postgres` é validado sem warning inesperado.
- [x] A leitura de saúde do cluster pode ser declarada “verde” sem depender de ressalva manual para esses três itens.

---

## References

- `oci-k8s-cluster/scripts/observability/cluster_health_check.sh`
- `components/kube-system/resource-quotas.yaml`
- `components/backup/snapshot-cronjob.yaml`
- `tasks/2026/Q2/T-124-Backup-Retention-Audit-and-ETCD-Recovery.md`
