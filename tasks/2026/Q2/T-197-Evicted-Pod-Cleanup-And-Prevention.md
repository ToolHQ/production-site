# T-197: Evicted Pod Cleanup + Prevenção de Acumulação

- **Status**: Backlog
- **Priority**: 🔽 Medium
- **Epic/Owner**: Infra / Ops / **Copilot/VSCode**
- **Estimation**: 1h
- **Opened**: 2026-05-16

## Context

Em 2026-05-16 foram identificados **24 pods `Evicted`** acumulados em `kube-system` (todos `snapshot-controller`), além de 1 pod `ContainerStatusUnknown` e 1 pod `Completed` stale em `cert-manager`.

Esses pods são consequência de evictions por `DiskPressure` no master e nunca são limpos automaticamente.
Acumulam indefinidamente, poluem o output de `kubectl get pods -A` e dificultam triagem de incidentes.

**Snapshot no momento do diagnóstico:**
```
kube-system: 24 × Evicted (snapshot-controller)
kube-system: 1 × ContainerStatusUnknown (snapshot-controller-7958d6d654-7ldvg)
cert-manager: 1 × Completed stale (cert-manager-cainjector-7994865bf9-4gjdl, 16d)
default: 5 × Completed stale (pre-pull jobs, 26d)
```

## Tasks

- [ ] Limpeza imediata: deletar todos os pods Failed/Evicted em `kube-system`
  ```bash
  kubectl delete pods -n kube-system --field-selector=status.phase=Failed
  ```
- [ ] Limpeza stale em outros namespaces:
  ```bash
  kubectl delete pods -n cert-manager --field-selector=status.phase=Succeeded --field-selector=status.phase=Failed 2>/dev/null || true
  kubectl delete pods -n default -l job-name --field-selector=status.phase=Succeeded 2>/dev/null || true
  ```
- [ ] Verificar: `kubectl get pods -A | grep -E 'Evict|Unknown|Error'` → deve retornar vazio
- [ ] Avaliar CronJob `failed-pod-cleaner` em `kube-system`:
  - Schedule: `0 */6 * * *` (a cada 6h)
  - Ação: `kubectl delete pods -A --field-selector=status.phase=Failed`
  - Namespace e RBAC mínimos necessários
- [ ] Criar manifesto IaC em `components/kube-system/failed-pod-cleaner.yaml` se o CronJob for aprovado
- [ ] Aplicar e validar no cluster

## References

- Incidente DiskPressure 2026-05-16 (T-193, T-196)
- `components/kube-system/` — manifests kube-system

## Validação

```bash
# Após limpeza imediata
kubectl get pods -A --field-selector=status.phase=Failed --no-headers | wc -l
# Esperado: 0

# Após CronJob (se criado)
kubectl get cronjob -n kube-system failed-pod-cleaner
```
