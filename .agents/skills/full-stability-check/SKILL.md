---
name: full-stability-check
description: |
  Checklist completo de estabilidade do cluster OCI K8s production-site.
  Cobre: infraestrutura, storage, rede, plataforma, observabilidade,
  aplicações e alinhamento IaC/TUI. Use sempre que quiser ter certeza
  que "tudo está 100% estável" antes de um dossier executivo.
---

# Full Stability Check — Production Site Cluster

> **Gatilho**: Quando o usuário pedir verificação completa do cluster, checklist de estabilidade, ou "garanta que tudo está estável".

## Pré-requisito: Tunnel Ativo

```bash
ssh -L 6445:localhost:6443 oci-k8s-master -N -f 2>/dev/null || true
export KUBECONFIG=/home/dnorio/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml
kubectl get nodes --no-headers   # espera: 4 Ready
```

---

## CHECKLIST (Ordem de Dependência Lógica)

### ✅ BLOCO 1 — INFRAESTRUTURA (base de tudo)

> Sem nós saudáveis e com disco/CPU/RAM ok, nada mais faz sentido verificar.

- [ ] **1.1 Nós Ready** → `kubectl get nodes`
  - Esperado: 4/4 Ready (master + node-1/2/3)
- [ ] **1.2 CPU/RAM por nó** → `kubectl top nodes`
  - Limites seguros: CPU <70%, RAM <85%
  - 🔴 node-2 RAM: atualmente 77% — monitorar
- [ ] **1.3 Disk headroom** → `ssh` em cada nó + `df -h /dev/sda1`
  - Limites seguros: <80% em todos os nós
  - 🔴 master & node-3: historicamente 81% — checar evolução
- [ ] **1.4 Systemd Journal limites** → `grep SystemMaxUse /etc/systemd/journald.conf`
  - Esperado: `SystemMaxUse=1G` em todos os nós
- [ ] **1.5 Logrotate agressivo** → `cat /etc/logrotate.d/rsyslog-aggressive`
  - Esperado: `maxsize 200M`, `rotate 3`, `su root adm` em todos os nós

#### Comandos Block 1
```bash
# 1.1 + 1.2
kubectl get nodes && kubectl top nodes

# 1.3 disk por nó
for n in oci-k8s-master oci-k8s-node-1 oci-k8s-node-2 oci-k8s-node-3; do
  echo -n "[$n] "; ssh "$n" "df -h /dev/sda1 | tail -1"
done

# 1.4 journal limits (todos nós)
for n in oci-k8s-master oci-k8s-node-1 oci-k8s-node-2 oci-k8s-node-3; do
  echo -n "[$n] "; ssh "$n" "grep SystemMaxUse /etc/systemd/journald.conf"
done
```

---

### ✅ BLOCO 2 — STORAGE (Longhorn + MinIO)

> Storage falho → backups falhos → cascata. Verificar antes de qualquer app.

- [ ] **2.1 Longhorn volumes** → todos Attached/Healthy
  - `kubectl get volumes.longhorn.io -n longhorn-system -o wide`
  - Nenhum volume em `Detached` ou `Degraded`
- [ ] **2.2 Longhorn backups** → 0 Error
  - `kubectl get backups.longhorn.io -n longhorn-system | grep Error` → deve ser vazio
- [ ] **2.3 Longhorn engine upgrades** → nenhuma pendente
  - `kubectl get engines.longhorn.io -n longhorn-system | grep -v 'v1.11.1'`
- [ ] **2.4 MinIO capacity** → <75%
  - `kubectl exec -n minio <pod> -- df -h /data`
  - 🎯 Target: <75% (watchdog WARN threshold)
- [ ] **2.5 MinIO backups por pasta** → k8s-backups + nexus crescimento saudável
  - `kubectl exec -n minio <pod> -- du -sh /data/*`
- [ ] **2.6 Hardening CronJobs ativos** → error-pruner + watchdog rodando
  - `kubectl get cronjob -n longhorn-system longhorn-error-backup-pruner`
  - `kubectl get cronjob -n minio minio-capacity-watchdog`
- [ ] **2.7 ETCD backups no master** → máx 4 arquivos
  - `ls -lh /var/backup/etcd/ | wc -l`

#### Comandos Block 2
```bash
# 2.1 Volumes
kubectl get volumes.longhorn.io -n longhorn-system --no-headers | awk '{print $1, $3, $4}'

# 2.2 Backups Error
kubectl get backups.longhorn.io -n longhorn-system -o custom-columns=NAME:.metadata.name,STATE:.status.state --no-headers | grep Error || echo "✅ 0 Error backups"

# 2.4 MinIO
MPOD=$(kubectl get pod -n minio -l app=minio -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n minio "$MPOD" -- df -h /data | tail -1
kubectl exec -n minio "$MPOD" -- du -sh /data/* 2>/dev/null
```

---

### ✅ BLOCO 3 — REDE (Ingress + Cilium/Hubble)

- [ ] **3.1 Ingress-nginx pods** → Running
  - `kubectl get pods -n ingress-nginx`
- [ ] **3.2 Ingress rules** → todas com HOSTS e ADDRESS
  - `kubectl get ingress -A --no-headers`
- [ ] **3.3 Cilium pods** → Running em todos os nós (1 por nó)
  - `kubectl get pods -n kube-system -l k8s-app=cilium`
- [ ] **3.4 HubbleUI** → pod Running + ingress reachable
  - `kubectl get pods -n kube-system -l k8s-app=hubble-ui`
  - Verify via ingress: `hubble.dnor.io` reachable
- [ ] **3.5 CoreDNS** → 2+ pods Running
  - `kubectl get pods -n kube-system -l k8s-app=kube-dns`
- [ ] **3.6 Cert-Manager** → pods Running + certificados válidos
  - `kubectl get cert -A`  — sem `False` em READY
  - `kubectl get cronjob -n cert-manager chain-repair` — ativo

#### Comandos Block 3
```bash
kubectl get pods -n ingress-nginx
kubectl get ingress -A --no-headers
kubectl get pods -n kube-system -l 'k8s-app in (cilium, hubble-ui, kube-dns)'
kubectl get cert -A --no-headers
```

---

### ✅ BLOCO 4 — PLATAFORMA (Nexus + Postgres)

- [ ] **4.1 Nexus pod** → Running, sem OOMKilled recente
  - `kubectl get pod -n nexus -o wide`
  - Memory usage: `kubectl top pod -n nexus`
- [ ] **4.2 Nexus blob store** → <80% capacity
  - Via API: `curl -s -u admin:<pwd> https://nexus.dnor.io/service/rest/v1/metrics/iq`
  - Ou via UI em nexus.dnor.io/admin/repository/blobstores
- [ ] **4.3 Nexus npm-proxy** → tamanho controlado
  - Verificar se limpeza automática está configurada (blob cleanup policy)
- [ ] **4.4 Postgres pods** → postgres-0 e postgres-1 Running
  - `kubectl get pods -n postgres`
- [ ] **4.5 Postgres snapshots** → últimos 7 CronJob runs Completed
  - `kubectl get jobs -n postgres --sort-by=.metadata.creationTimestamp | tail -7`
- [ ] **4.6 Postgres PVCs** → Bound, sem Resize pending
  - `kubectl get pvc -n postgres`

#### Comandos Block 4
```bash
kubectl get pod -n nexus -o wide && kubectl top pod -n nexus
kubectl get pods -n postgres
kubectl get pvc -n postgres
kubectl get jobs -n postgres --sort-by=.metadata.creationTimestamp --no-headers | tail -7
```

---

### ✅ BLOCO 5 — OBSERVABILIDADE (Coroot + Kubecost + K8s Dashboard)

- [ ] **5.1 Coroot pods** → coroot, clickhouse, prometheus, node-agents todos Running
  - `kubectl get pods -n coroot`
- [ ] **5.2 Coroot alertas** → 0 alertas ativos (CRÍTICO)
  - Via UI: `https://coroot.dnor.io` → Check → sem alertas em vermelho
- [ ] **5.3 Coroot ClickHouse disk** → PVC não crítico
  - `kubectl get pvc -n coroot`
- [ ] **5.4 Kubecost pods** → Running
  - `kubectl get pods -n kubecost`
- [ ] **5.5 Kubernetes Dashboard** → pod Running + ingress ativo
  - `kubectl get pods -n kubernetes-dashboard`
  - `kubectl get ingress -n kubernetes-dashboard`
- [ ] **5.6 Metrics-server** → disponível (para kubectl top funcionar)
  - `kubectl get deployment -n kube-system metrics-server`

#### Comandos Block 5
```bash
kubectl get pods -n coroot && kubectl get pvc -n coroot
kubectl get pods -n kubecost
kubectl get pods -n kubernetes-dashboard
kubectl get deployment -n kube-system metrics-server
```

---

### ✅ BLOCO 6 — CLUSTER NATIVO (ETCD + kube-system core)

- [ ] **6.1 Control plane pods** → kube-apiserver, etcd, scheduler, controller-manager → Running
  - `kubectl get pods -n kube-system | grep -E '(apiserver|etcd|scheduler|controller)'`
- [ ] **6.2 ETCD backup CronJobs** → última execução Completed
  - `kubectl get cronjob -n kube-system etcd-backup etcd-backup-prune`
- [ ] **6.3 ETCD snapshot files** → máx 5 arquivos no master
  - `ssh oci-k8s-master "ls -lh /var/backup/etcd/ | wc -l"`
- [ ] **6.4 Cilium health** → `cilium status` OK
  - `kubectl exec -n kube-system ds/cilium -- cilium status --brief`

#### Comandos Block 6
```bash
kubectl get pods -n kube-system | grep -E '(apiserver|etcd|scheduler|controller)'
kubectl get cronjob -n kube-system
ssh oci-k8s-master "ls -lh /var/backup/etcd/"
```

---

### ✅ BLOCO 7 — APLICAÇÕES (default + ai-radar)

- [ ] **7.1 Pods no namespace `default`** → todos Running
  - `kubectl get pods -n default`
  - Verificar: torproxy, reports, rs-* services
- [ ] **7.2 Pods no namespace `ai-radar`** → Running (API + DB + Jobs)
  - `kubectl get pods -n ai-radar`
- [ ] **7.3 AI-Radar CronJobs** → collect/extract/score últimas runs OK
  - `kubectl get jobs -n ai-radar --sort-by=.metadata.creationTimestamp | tail -5`
- [ ] **7.4 Ingress de apps** → todas com endereço e certificado válido
  - `kubectl get ingress -n default -n ai-radar 2>/dev/null || kubectl get ingress -A | grep -E '(default|ai-radar)'`
- [ ] **7.5 Nenhum pod em CrashLoop/OOMKilled/Pending em qualquer namespace**
  - `kubectl get pods -A | grep -vE '(Running|Completed|Succeeded)'`

#### Comandos Block 7
```bash
kubectl get pods -n default
kubectl get pods -n ai-radar
kubectl get jobs -n ai-radar --sort-by=.metadata.creationTimestamp --no-headers | tail -5
kubectl get pods -A --no-headers | grep -vE '(Running|Completed|Succeeded)' || echo "✅ All pods healthy"
```

---

### ✅ BLOCO 8 — IaC/TUI ALIGNMENT

- [ ] **8.1 Git status limpo** → sem arquivos modificados não commitados em main
  - `git status --short`
- [ ] **8.2 Todos CronJobs com YAML no repo** → nenhum hand-applied
  - Mapear: `kubectl get cronjob -A --no-headers` vs `find components apps -name "*.yaml" | xargs grep -l "kind: CronJob"`
- [ ] **8.3 Drift detection** → reaplicar todos manifests com --dry-run=client
  - `kubectl apply -f components/backup/ --dry-run=client 2>&1 | grep -v unchanged`
- [ ] **8.4 IaC hardening scripts aplicados em todos nós**
  - Verificar: `/etc/logrotate.d/rsyslog-aggressive` existe em todos os 4 nós
  - Verificar: `/etc/systemd/journald.conf` tem `SystemMaxUse=1G` em todos
- [ ] **8.5 TUI integração** → k8s_ops_menu.sh cobre backup/hardening ops

#### Comandos Block 8
```bash
git -C /home/dnorio/production-site status --short

# CronJobs no cluster vs repo
kubectl get cronjob -A --no-headers | awk '{print $1"/"$2}'
find /home/dnorio/production-site/components /home/dnorio/production-site/apps -name "*.yaml" | xargs grep -l "kind: CronJob" 2>/dev/null

# Dry-run drift check
export KUBECONFIG=/home/dnorio/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml
kubectl apply -f /home/dnorio/production-site/components/backup/ --dry-run=client 2>&1 | grep -v "unchanged\|dry-run"

# Hardening nos nós
for n in oci-k8s-master oci-k8s-node-1 oci-k8s-node-2 oci-k8s-node-3; do
  echo -n "[$n] rsyslog-aggressive: "
  ssh "$n" "test -f /etc/logrotate.d/rsyslog-aggressive && echo '✅' || echo '❌ MISSING'"
done
```

---

## SEMÁFORO FINAL

Após executar todos os blocos, avaliar:

| Cor | Critério |
|-----|----------|
| 🟢 Verde | Todos os checks OK, nenhum risco imediato |
| 🟡 Amarelo | 1-2 itens WARNING (ex.: RAM 77%, Disk 81%) — monitorar |
| 🔴 Vermelho | Qualquer pod em Error/CrashLoop, Disk >90%, MinIO >85%, Error backups >0 |

## Histórico de Execuções Notáveis

| Data | Problema | Ação | Resultado |
|------|----------|------|-----------|
| 2026-05-10 | MinIO 100%, 53 Error backups | Limpeza + PR #90 (hardening CronJobs) | MinIO 32%, 0 Error |
| 2026-05-10 | node-3 /var/log 4.5GB (syslog.1) | Logrotate aggressive + su root adm fix | 1.6GB (-2.9GB) |
| 2026-05-10 | maintenance-cleanup drift IaC vs cluster | kubectl apply -f cleanup-job.yaml | Drift corrigido |
