# T-192: Control Plane Hardening — Apiserver + Cilium + Etcd (pós-outage 12/Mai)

- **Status**: Backlog
- **Priority**: 🚨 Critical
- **Epic/Owner**: Infra / Ops
- **Estimation**: 4h
- **Opened**: 2026-05-13

## Context

**Incidente 12/Mai/2026 04:00–07:42 UTC**: `kube-apiserver` entrou em deadlock de
goroutines (~350h de CPU acumulado em 4 dias). Accept queue saturou (4097/4096).
TLS handshake timeout para todos os clientes — cluster completamente inacessível.
Cascade failure: 12 componentes crasharam em 11 minutos.

| Componente | Restarts | Causa direta |
|---|---|---|
| cilium-operator | 134 | apiserver inacessível |
| snapshot-controller | 80 | apiserver inacessível |
| csi-provisioner (longhorn) | 79 | apiserver inacessível |
| kube-controller-manager | 36 | apiserver inacessível |
| kube-scheduler | 29 | apiserver inacessível |

**Root causes confirmadas via diagnóstico 13/Mai:**

1. **Sem `livenessProbe` no kube-apiserver** — apenas `startupProbe` existe.
   Após startup, nenhuma probe detecta deadlock → outage durou horas sem auto-restart.
   `grep livenessProbe /etc/kubernetes/manifests/kube-apiserver.yaml` → vazio.

2. **Sem `--max-requests-inflight`/`--max-mutating-requests-inflight`** no manifest.
   Apiserver aceita goroutines ilimitadas. Com 1 vCPU: sem backpressure, acumulam
   até deadlock. Padrão upstream upstream recomendado para ambiente constrained: 150/50.

3. **Cilium `operator.numWorkers` não configurado** (default implícito: alto).
   `taint-sync-workers: 10` no runtime. Não há override em
   `components/cilium/cilium-values.yaml`. 10 goroutines concorrentes martelando
   apiserver de dentro, amplificando pressão sobre watch/lease machinery.

4. **Etcd sem `--auto-compaction-retention`** — revision history cresce
   indefinidamente, aumentando watch pressure com o tempo.
   `grep auto-compaction /etc/kubernetes/manifests/etcd.yaml` → vazio.
   Sem `--quota-backend-bytes` → risco silencioso de `database space exceeded`.

5. **Node-2 overcommit extremo** — 33 pods, CPU requests 88% (706m/800m),
   CPU limits 1137% (9100m/800m). snapshot-controller e csi-provisioner
   (os com mais restarts após apiserver) residem neste nó.

### Gap de Sincronia IaC vs Cluster (CRÍTICO)

> **Todos os itens abaixo são gaps ativos: o cluster tem configurações que não
> existem no repositório. Um rebuild do zero reproduziria as mesmas falhas.**

| Config Necessária | Onde deveria estar | Estado atual |
|---|---|---|
| `livenessProbe` no kube-apiserver | `components/kube-system/commands.sh` | ❌ AUSENTE |
| `--max-requests-inflight=150` | `components/kube-system/commands.sh` | ❌ AUSENTE |
| `--max-mutating-requests-inflight=50` | `components/kube-system/commands.sh` | ❌ AUSENTE |
| `operator.numWorkers: 2` no Cilium | `components/cilium/cilium-values.yaml` | ❌ AUSENTE |
| `--auto-compaction-retention=8h` no etcd | `components/kube-system/commands.sh` | ❌ AUSENTE |
| `--quota-backend-bytes=1610612736` no etcd | `components/kube-system/commands.sh` | ❌ AUSENTE |
| `nodeAffinity` nos deployments de node-2 | manifests dos componentes | ❌ AUSENTE |
| Alerta apiserver liveness no Coroot | `components/coroot/` | ❌ AUSENTE |

## Tasks

### Fase 1 — Apiserver: livenessProbe + Request Throttling (🚨 CRÍTICO)

> **IaC obrigatória**: cada mudança no manifest live deve ser codificada em
> `components/kube-system/commands.sh` (invocado por `tune_control_plane_resources`
> em `oci-k8s-cluster/setup_k8s_cluster.sh`). Rebuild do zero deve herdar isso.

- [ ] **[LIVE]** Adicionar `livenessProbe` em `/etc/kubernetes/manifests/kube-apiserver.yaml`:
  ```yaml
  livenessProbe:
    failureThreshold: 3
    httpGet:
      host: 10.0.1.100
      path: /livez
      port: 6443
      scheme: HTTPS
    initialDelaySeconds: 10
    periodSeconds: 30
    timeoutSeconds: 10
  ```
  → kubelet detecta deadlock e reinicia em ≤90s
- [ ] **[LIVE]** Adicionar flags ao manifest do kube-apiserver:
  - `- --max-requests-inflight=150`
  - `- --max-mutating-requests-inflight=50`
- [ ] **[IaC]** Codificar `livenessProbe` e ambos os flags em
  `components/kube-system/commands.sh` (função `patch_manifest` ou patch dedicado),
  para que `tune_control_plane_resources` os aplique em rebuilds futuros.
- [ ] Validar restart automático do static pod pelo kubelet (< 60s).
- [ ] Validar `kubectl get nodes` responde normalmente após restart.
- [ ] Validar `curl -k https://10.0.1.100:6443/livez` retorna `ok` do master.

### Fase 2 — Cilium: Reduzir Concorrência do Operator

> **IaC obrigatória**: `components/cilium/cilium-values.yaml` é o source of truth
> para o Cilium. O `components/cilium/commands.sh` aplica via `cilium upgrade install --values`.

- [ ] **[IaC]** Adicionar em `components/cilium/cilium-values.yaml`:
  ```yaml
  operator:
    numWorkers: 2        # default implícito ~10 — muito alto para 1 vCPU
  ```
- [ ] **[LIVE]** Aplicar via:
  ```bash
  cd components/cilium && bash commands.sh
  ```
  ou patch direto se upgrade não disponível:
  ```bash
  kubectl patch configmap cilium-config -n kube-system \
    --type merge -p '{"data":{"operator-num-workers":"2"}}'
  kubectl rollout restart deployment cilium-operator -n kube-system
  ```
- [ ] Validar cilium-operator Running e sem crash loop pós-configuração.
- [ ] Confirmar no ConfigMap: `kubectl get cm -n kube-system cilium-config -o jsonpath='{.data.operator-num-workers}'`.

### Fase 3 — Etcd: Compaction + Quota + Defrag

> **IaC obrigatória**: `components/kube-system/commands.sh` → função `patch_manifest`
> já patcha etcd resources. Adicionar os dois flags de compaction no mesmo fluxo.

- [ ] **[LIVE]** Adicionar no static pod `/etc/kubernetes/manifests/etcd.yaml`:
  - `- --auto-compaction-retention=8h`
  - `- --quota-backend-bytes=1610612736`   (1.5 GiB — seguro para este cluster)
- [ ] **[IaC]** Codificar ambos os flags em `components/kube-system/commands.sh`
  via `patch_manifest` ou snippet `sudo sed -i` após o bloco de resources do etcd.
- [ ] Validar restart do static pod do etcd (kubelet, < 60s).
- [ ] Validar etcd saudável:
  ```bash
  ssh oci-k8s-master 'sudo etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    endpoint health'
  ```
- [ ] Executar defrag manual inicial (limpeza acumulada):
  ```bash
  ssh oci-k8s-master 'sudo etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    defrag'
  ```
- [ ] Verificar DB size antes/depois:
  `etcdctl endpoint status -w table` → coluna `DB SIZE`.

### Fase 4 — Node Rebalancing (node-2 → node-3)

> **IaC obrigatória**: qualquer `nodeAffinity` ou `podAntiAffinity` adicionada
> deve residir nos manifests em `components/` ou patches Kustomize, não apenas live.

- [ ] Auditar candidatos a migrar do node-2 (33 pods, 88% CPU requests) para node-3 (27 pods):
  - `snapshot-controller` (80 restarts, no node-2) — adicionar `nodeAffinity` preferindo node-3
  - `hubble-relay` / `hubble-ui` — baixo impacto, mobile
  - Um dos dois `coredns` — atualmente ambos em node-2
- [ ] Para cada candidato: adicionar `podAntiAffinity` ou `preferredDuringScheduling nodeAffinity`
  no manifest do deployment em `components/kube-system/`.
- [ ] Validar após redistribuição: node-2 CPU requests < 70%.
  `kubectl describe node k8s-node-2 | grep -A10 "Allocated"`

### Fase 5 — Observability & Alerting

> **IaC obrigatória**: configurações do Coroot devem estar em `components/coroot/`
> para serem reaplicadas em rebuild. Ver `T-102` como referência.

- [ ] Verificar se Coroot já tem dashboard de accept queue / goroutines do apiserver.
- [ ] Configurar alerta no Coroot (ou via configmap coroot) para:
  - kube-apiserver: latência p99 > 1s por > 5 min → `alert: warning`
  - kube-apiserver: restart count > 0 → `alert: critical` (imediato)
  - Qualquer nó: CPU usage > 85% por > 10 min → `alert: warning`
- [ ] **[IaC]** Documentar/exportar configuração do alerta para `components/coroot/`.

### Fase 6 — TUI Hardening Menu: Adicionar Validação de Control Plane

> **IaC obrigatória**: o menu de Hardening da TUI (`k8s_ops_menu.sh` → `show_hardening_menu`)
> deve incluir uma opção de "Verificar Control Plane" para checagem rápida dos itens desta task.

- [ ] Adicionar opção `"4" "Verify Control Plane Config"` em `show_hardening_menu`
  (`oci-k8s-cluster/k8s_ops_menu.sh` linha ~4110) que execute:
  - `grep livenessProbe /etc/kubernetes/manifests/kube-apiserver.yaml` (deve existir)
  - `grep max-requests-inflight /etc/kubernetes/manifests/kube-apiserver.yaml` (deve existir)
  - `grep auto-compaction /etc/kubernetes/manifests/etcd.yaml` (deve existir)
  - `kubectl get cm -n kube-system cilium-config -o jsonpath='{.data.operator-num-workers}'` (deve ser `2`)
  - `kubectl top nodes` (snapshot de pressão atual)

### Fase 7 — Documentação e Postmortem

- [ ] Atualizar `AGENTS.md` e skills relevantes para mencionar que:
  - `livenessProbe` no apiserver é **obrigatório** em qualquer setup
  - `--max-requests-inflight` deve ser configurado em ambientes ≤ 1 vCPU
  - `components/kube-system/commands.sh` é o IaC de controle plane tuning
- [ ] Registrar postmortem resumido em `logs/` ou `docs/` (data, causa, impacto, resolução).

## DoD

- `kube-apiserver` tem `livenessProbe` funcional — reiniciaria em ≤90s em deadlock.
- `kubectl get nodes` responde em < 500ms consistentemente.
- `grep livenessProbe /etc/kubernetes/manifests/kube-apiserver.yaml` → não vazio.
- `grep max-requests-inflight /etc/kubernetes/manifests/kube-apiserver.yaml` → `150`.
- `kubectl get cm -n kube-system cilium-config -o jsonpath='{.data.operator-num-workers}'` → `2`.
- `grep auto-compaction /etc/kubernetes/manifests/etcd.yaml` → `8h`.
- Node-2 CPU requests < 70% (`kubectl describe node k8s-node-2 | grep "Allocated" -A5`).
- Todos os itens do gap IaC marcados como aplicados.
- `components/kube-system/commands.sh` e `components/cilium/cilium-values.yaml` refletem o estado do cluster.
- TUI Hardening menu tem opção "Verify Control Plane".

## Validação Completa

```bash
# === Fase 1: apiserver ===
ssh oci-k8s-master 'sudo grep -A10 livenessProbe /etc/kubernetes/manifests/kube-apiserver.yaml'
ssh oci-k8s-master 'sudo grep max-requests /etc/kubernetes/manifests/kube-apiserver.yaml'

# === Fase 2: cilium ===
kubectl get cm -n kube-system cilium-config -o jsonpath='{.data.operator-num-workers}'
# esperado: 2

# === Fase 3: etcd ===
ssh oci-k8s-master 'sudo grep auto-compaction /etc/kubernetes/manifests/etcd.yaml'
ssh oci-k8s-master 'sudo grep quota-backend /etc/kubernetes/manifests/etcd.yaml'

# === Fase 4: node balance ===
kubectl top nodes
kubectl get pods -A -o wide | grep k8s-node-2 | wc -l
kubectl describe node k8s-node-2 | grep -A8 "Allocated resources"

# === IaC sync check ===
grep livenessProbe components/kube-system/commands.sh
grep max-requests components/kube-system/commands.sh
grep auto-compaction components/kube-system/commands.sh
grep numWorkers components/cilium/cilium-values.yaml
grep "Verify Control Plane" oci-k8s-cluster/k8s_ops_menu.sh
```

## References

- **Incidente**: kube-apiserver deadlock 2026-05-12 ~04:00–07:42 UTC (cascade failure, 12 componentes, ~4h down)
- **IaC de control plane tuning**: `components/kube-system/commands.sh` (invocado por `setup_k8s_cluster.sh:tune_control_plane_resources`)
- **IaC Cilium**: `components/cilium/cilium-values.yaml` + `components/cilium/commands.sh`
- **IaC setup geral**: `oci-k8s-cluster/setup_k8s_cluster.sh`
- **TUI Hardening menu**: `oci-k8s-cluster/k8s_ops_menu.sh` linha ~4097 (`show_hardening_menu`)
- **Skill Cluster Maintenance**: `.agents/skills/cluster-maintenance-protocols/SKILL.md`
- **Skill Operational Safety**: `.agents/skills/operational-safety/SKILL.md`
- **Causa anterior similar**: T-102/T-103 (CPU starvation / Longhorn 2026-04-03)
- **Kubernetes docs**: `--max-requests-inflight`, `livenessProbe` em static pods
- Branch sugerida: `infra/T-192-control-plane-hardening`
