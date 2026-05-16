# T-198: cert-manager-cainjector Stability Investigation

- **Status**: Done ✅ — Fixed by T-196 (2026-05-16)
- **Priority**: 🔽 Low
- **Epic/Owner**: Infra / Ops / **Copilot/VSCode**
- **Estimation**: 1h
- **Opened**: 2026-05-16

## Context

O pod `cert-manager-cainjector-7994865bf9-fnwvc` acumulou **77 restarts** em 11 dias (node-3).
- Último crash: 2026-05-13 02:00 (exit code 1, não OOMKilled)
- Desde então: estável há ~3 dias
- Há também um pod stale `Completed` no node-1 (16d)

O cainjector é responsável por injetar CA bundles em webhooks. Instabilidade prolongada pode causar falhas silenciosas em validação de certificados.

## Hipóteses

| Hipótese | Probabilidade | Como verificar |
|---|---|---|
| Crash durante DiskPressure no master (apiserver indisponível) | Alta | Correlacionar timestamps de restarts com eventos DiskPressure |
| Bug de leader election (dois cainjector competindo) | Média | Verificar logs de ambos os pods |
| Memory pressure no node-3 | Baixa | `kubectl top node k8s-node-3` |

## Tasks

- [x] Coletar logs do cainjector — último crash coletado via `--previous`
- [x] **Causa raiz confirmada**: `connection refused` no apiserver `10.96.0.1:443`
  ```
  E0516 18:27:07 main.go:45] failed to get API group resources: unable to retrieve
  the complete list of server APIs: apiextensions.k8s.io/v1: dial tcp 10.96.0.1:443:
  connect: connection refused
  ```
  O apiserver fica inacessível durante episódios de DiskPressure no master → cainjector crasha com exit code 1 (não OOMKilled)
- [x] Correlação: último crash 2026-05-13 02:00 coincide com DiskPressure do BuildKit (T-193/T-196)
- [x] Pod stale `cert-manager-cainjector-7994865bf9-4gjdl` (Completed, 16d) deletado
- [x] **Solução**: DiskPressure prevenida por T-196 (postbuild_buildkit_prune) — não é bug do cert-manager
- [x] Cert-manager: 3 pods Running, 0 restarts recentes ✅

## References

- T-192 — Control Plane Hardening (outage 12/Mai)
- T-193/T-196 — DiskPressure master
- T-128 — Cluster Yellow-State Cleanup (cert-manager quota anterior)

## Validação

```bash
# Saúde geral dos certs
kubectl get certificates -A | grep -v True
# Esperado: vazio (todos True/Ready)

# Cainjector rodando saudável
kubectl get pods -n cert-manager | grep cainjector
# Esperado: 1/1 Running, < 5 restarts recentes
```
