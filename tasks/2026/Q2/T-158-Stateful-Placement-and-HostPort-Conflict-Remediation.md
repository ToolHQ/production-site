# T-158: Stateful Placement and HostPort Conflict Remediation

- **Status**: In Progress
- **Priority**: 🔼 High
- **Epic/Owner**: Infra / Platform
- **Estimation**: 1d
- **Opened**: 2026-05-01

## Context

Durante a mitigacao da T-157, o cluster expôs gargalos estruturais de agendamento em ambiente de baixo recurso:

- `postgres` opera com `hostNetwork: true` e `containerPort 5432`;
- `ingress-nginx` worker tambem ocupa `hostPort 5432` em node worker;
- com `node-3` cordoned, o scheduler ficou sem envelope consistente para `postgres-1` em alguns ciclos;
- conflitos de quota em `nexus-quota` e `kubecost-quota` causaram falhas transitorias de `FailedCreate` durante churn de pods.

## Problem Statement

A plataforma ficou funcionalmente dependente de combinacoes especificas de node/porta para workloads stateful e de observabilidade, reduzindo resiliência em falhas de um unico node.

## Treatment Strategy

1. **Scheduling discipline**
- revisar e reduzir uso de `hostNetwork`/`hostPort` em workloads nao estritamente obrigatorios;
- manter anti-affinity apenas onde agrega resiliencia real no envelope de 4 nodes;
- garantir que postgres replica secundaria tenha rota de agendamento viavel quando um worker estiver isolado.

2. **Quota hygiene by workload class**
- recalibrar `nexus-quota` e `kubecost-quota` para absorver ciclos de recriacao sem `FailedCreate` em rollout;
- manter requests/limits aderentes ao budget do cluster (stability first).

3. **Operational playbook**
- registrar procedimento de degradacao controlada: `cordon`, reschedule seletivo, criterios de `uncordon`;
- explicitar dependencias de porta por node para evitar lock acidental em incidentes.

## DoD

- [ ] mapa versionado de `hostPort` criticos por namespace/workload.
- [ ] plano aplicado para eliminar ou reduzir conflito de `5432` entre ingress e postgres no caminho de failover.
- [ ] `postgres-1` com estrategia de agendamento resiliente sem depender exclusivamente do `k8s-node-3`.
- [ ] `nexus` e `kubecost` sem `FailedCreate` por quota durante rollout/recreate controlado.
- [ ] runbook de incidente atualizado com fluxo de cordon/reschedule/uncordon e verificacoes minimas.

## Rationale

No cluster ARM64 de 1 vCPU por node, estabilidade depende mais de envelopes operacionais previsiveis do que de throughput maximo. Conflitos de hostPort e quotas sem buffer transformam qualquer flapping em outage em cascata.

## References

- `tasks/2026/Q2/T-157-Longhorn-Quota-Headroom-and-Node3-Recovery.md`
- `components/kube-system/resource-quotas.yaml`
- `components/ingress-nginx/deploy.yaml`
- `components/postgres/postgres-resources.yaml`
