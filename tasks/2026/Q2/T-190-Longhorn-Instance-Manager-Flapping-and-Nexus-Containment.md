# T-190 — Longhorn Instance-Manager Flapping and Nexus Containment

- **Status**: 🚧 In Progress
- **Priority**: 🚨 Critical
- **Owner**: Infra / Storage
- **Created**: 2026-05-01

## Context

Após a recuperacao inicial do incidente de storage, o cluster manteve sinais de instabilidade no Longhorn:

- Reinicios recorrentes do `instance-manager` no node-1.
- Erros de conectividade interna Longhorn (`:8501` e `:8503`) em eventos recentes.
- Volumes em `faulted`/`detaching` e parte em `degraded`.
- Oscilacao de pods stateful (Postgres, Coroot ClickHouse, Kubecost em janelas diferentes).

Nexus voltou a responder `200`, mas com risco residual de regressao enquanto o Longhorn nao convergir.

## Evidence Snapshot (2026-05-01)

- `https://longhorn.dnor.io` -> `HTTP 200`
- `https://nexus.dnor.io` -> `HTTP 200`
- Volume do postgres (`pvc-fd9d35d1-ba96-4636-aaee-3023d996d112`) observado em `detaching/faulted` durante a janela de verificacao.
- Eventos Longhorn com `FailedStopping`, `DetachedUnexpectedly`, `FailedRebuilding` e `connection refused` para `instance-manager`.

## Mitigations Applied

1. Patch operacional em Longhorn setting:
   - `instance-manager-pod-liveness-probe-timeout=30`
2. Contencao do Nexus para reduzir impacto imediato:
   - `nodeSelector: kubernetes.io/hostname=k8s-node-2`
3. Reciclagem/reattach operacional pontual:
   - remocao cirurgica de `VolumeAttachment` preso quando necessario.

## Repo Changes (versioned)

- Persistido `nodeSelector` temporario do Nexus em `components/nexus/nexus.yaml`.
- KANBAN atualizado para estado amarelo e rastreamento da tarefa critica.

## Exit Criteria

- `instance-manager` do node-1 sem reinicios por janela minima de 30 min.
- Volumes criticos sem `faulted/detaching` (alvo: apenas `healthy` ou `degraded` transitivo em reconstrucao controlada).
- `postgres-0` estavel (`Ready 1/1`) sem `FailedMount` por pelo menos 20 min.
- `nexus.dnor.io` sustentando `200` sem regressao durante a mesma janela.

## Next Actions

1. Rodar monitoramento temporal (pods/eventos/volumes) em janela de 30 min.
2. Validar convergencia de replicas para volumes criticos no Longhorn UI e via CRD.
3. Se houver novo flapping, escalar para runbook de manutencao de node-1 (modo seguro, sem acao destrutiva em stateful).
