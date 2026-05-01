# T-157: Longhorn Quota Headroom and Node-3 Recovery

- **Status**: In Progress
- **Priority**: 🚨 Critical
- **Epic/Owner**: Infra / Storage
- **Estimation**: 1d
- **Opened**: 2026-05-01

## Context

Em 2026-05-01 o cluster entrou em degradacao em cascata com `Nexus`, `MinIO`, `Coroot`, `Kubecost` e `Postgres` fora de `Running`.

A investigacao live confirmou que os nodes estavam `Ready` e sem `MemoryPressure`/`DiskPressure` no kubelet, mas o plano de controle de storage estava estrangulado:

- `longhorn-quota` em `limits.memory=8Gi` com `used=8Gi`;
- falha recorrente de criacao de pods de suporte Longhorn (`discover-proc-kubelet-cmdline`, jobs de backup/maintenance, `instance-manager`);
- volumes em `attaching` com `VolumeAttachment` preso;
- blast radius concentrado no `k8s-node-3`.

## Root Cause Confirmed

- a quota de memoria do namespace `longhorn-system` ficou sem folga operacional;
- baseline de limites do proprio Longhorn ja consumia `8Gi`, deixando `0Mi` para reconciliacao;
- o `instance-manager` do `k8s-node-3` permaneceu em estado `error`, impedindo o ciclo de attach/engine para volumes que estavam naquela trilha;
- efeito em cadeia: pods stateful de namespaces criticos ficaram em `ContainerCreating`/`Init` por timeout de attach.

## Live Mitigation Executed

- patch aplicado em producao:
  - `longhorn-quota.spec.hard.limits.memory: 8Gi -> 12Gi`;
- `longhorn-driver-deployer` recriado para forcar reconciliacao;
- `k8s-node-3` foi `cordon` para estabilizar scheduling e reduzir recorrencia imediata;
- pods criticos travados foram recriados para reescalonar em nodes saudaveis;
- attachments antigos do node-3 foram substituidos por novos attachments em node-1/node-2.

## Repo/TUI Sync (Versioned)

- manifesto de quota atualizado em:
  - `components/kube-system/resource-quotas.yaml`
- esse arquivo e o source aplicado pela rotina de quotas usada pela operacao/TUI via:
  - `components/kube-system/commands.sh`

## Plan to Close

1. estabilizar `Nexus`, `Kubecost`, `MinIO`, `Coroot` e `Postgres` no estado pos-mitigacao;
2. remover dependencia funcional de `k8s-node-3` para PVCs criticos durante janela de incidente;
3. validar `longhorn-system` sem novos `FailedCreate` por quota;
4. definir envelope minimo de headroom para quota Longhorn (nao operar mais no limite); 
5. fechar a task com evidencias de convergencia e risco residual documentado.

## DoD

- [ ] `longhorn-quota` aplicado e versionado com headroom operacional (nao saturado no steady-state).
- [ ] `longhorn-driver-deployer` sem `CrashLoopBackOff` por quota.
- [ ] sem novos eventos `FailedCreate ... exceeded quota: longhorn-quota` por pelo menos 1 ciclo de jobs Longhorn.
- [ ] sem pods criticos presos em `ContainerCreating` por `FailedAttachVolume` referente ao incidente de 2026-05-01.
- [ ] evidencias anexadas na task (eventos, status de pods e attachments).
- [ ] KANBAN atualizado refletindo status real da recuperacao.

## Risks and Notes

- `k8s-node-3` continua com `instance-manager` em trilha de erro e requer remediacao estruturada fora do hotfix.
- manter node cordoned reduz blast radius imediato, mas afeta capacidade de scheduling para workloads com restricoes fortes.

## References

- `components/kube-system/resource-quotas.yaml`
- `components/kube-system/commands.sh`
- `tasks/2026/Q2/T-149-Master-DiskPressure-Recurrence-Hardening.md`
- `tasks/2026/Q2/T-153-MinIO-Longhorn-Gate-Correction-and-Nexus-Exhaustion.md`
