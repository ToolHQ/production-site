# T-197: Evicted Pod Cleanup + Prevenção de Acumulação

- **Status**: Done ✅ (2026-05-16)
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

- [x] Limpeza imediata: deletar todos os pods Failed/Evicted em `kube-system`
  ```bash
  kubectl delete pods -n kube-system --field-selector=status.phase=Failed
  # Resultado: 25 pods Evicted deletados
  ```
- [x] Limpeza stale em outros namespaces (cert-manager + default)
- [x] Verificar: `kubectl get pods -A | grep -E 'Evict|Unknown|Error'` → retornou vazio ✅
- [x] CronJob `failed-pod-cleaner` criado e aplicado:
  - Schedule: `0 */6 * * *` (a cada 6h)
  - Manifesto IaC: `components/kube-system/failed-pod-cleaner.yaml`
  - RBAC: ServiceAccount + ClusterRole (list/delete pods) + ClusterRoleBinding
  - Imagem: `bitnami/kubectl:1.31`, requests 10m/32Mi, limits 50m/64Mi
- [x] Aplicado e validado: `kubectl get cronjob -n kube-system failed-pod-cleaner` → Active

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
