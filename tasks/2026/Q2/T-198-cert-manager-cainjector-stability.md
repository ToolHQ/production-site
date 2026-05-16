# T-198: cert-manager-cainjector Stability Investigation

- **Status**: Backlog
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

- [ ] Coletar logs do cainjector para os últimos crashes:
  ```bash
  kubectl logs -n cert-manager cert-manager-cainjector-7994865bf9-fnwvc --previous 2>/dev/null | tail -50
  ```
- [ ] Correlacionar timestamps de restart com DiskPressure events no master
- [ ] Verificar se há dois cainjectors em estado `Running` simultaneamente (leader election problem)
- [ ] Deletar pod stale `cert-manager-cainjector-7994865bf9-4gjdl` (Completed, node-1, 16d)
- [ ] Verificar saúde do cert-manager: `kubectl get certificates -A` e `kubectl get certificaterequests -A`
- [ ] Se causa for DiskPressure: marcar como "fixed por T-196" e fechar
- [ ] Se causa for bug: abrir fix ou ajustar resources

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
