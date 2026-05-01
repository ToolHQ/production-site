# T-174: AI Radar — Kubernetes Baseline (primeiro deploy API)

- **Status**: In Progress
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp / Infra
- **Estimation**: 4h
- **Opened**: 2026-05-01

## Context

**Onda 1** do deploy no cluster: colocar apenas a **API** (`ai-radar-api`) no OCI ARM64 com Postgres compartilhado, **antes** de digest/CronJobs completos. Objetivo é **validar incrementalmente** pull de imagem Nexus, probes, limites reais, `DATABASE_URL`, migrações contra o banco de produção e roteamento interno — sem esperar T-169/T-171.

Seguir `deploy-service` e `operational-safety` (`AGENTS.md`). Não alterar workloads stateful críticos (Postgres primário, Nexus, Longhorn).

**T-171** continua como **onda 2** (CronJobs, quotas adicionais, smoke completo demo-ready).

## Tasks

- [x] `apps/ai-radar/k8s/base/namespace.yaml` — namespace dedicado `ai-radar`
- [x] `apps/ai-radar/k8s/base/serviceaccount.yaml` — SA dedicada, sem RBAC cluster-wide desnecessário
- [x] `apps/ai-radar/k8s/base/deployment-api.yaml` — `replicas: 1`, `ai-radar-api`, `securityContext` endurecido, probes em `GET /health`, resources 25m/64Mi → 250m/256Mi
- [x] `apps/ai-radar/k8s/base/service.yaml` — ClusterIP :8080
- [x] `apps/ai-radar/k8s/base/configmap.yaml` — envs não secretas (`AI_RADAR_LOG_LEVEL`)
- [x] `apps/ai-radar/k8s/base/secret-database-url.placeholder.yaml` — `DATABASE_URL` com placeholder + `?options=-csearch_path%3Dpublic`; documentação SealedSecrets/SOPS no README
- [x] Runbook de migrações: distroless sem shell → `README` (estação tooling / `just migrate`, não `exec … wget`)
- [x] `imagePullSecrets: regsecret` (igual outros serviços ARM64 Nexus)
- [x] `k8s/base/kustomization.yaml` + `k8s/overlays/production/kustomization.yaml`
- [x] `apps/ai-radar/deploy.sh` — build `docker/Dockerfile.api`, push ARM64, `kubectl apply` via Kustomize render + substituição de tag
- [x] `just k8s-validate` + `kubectl apply --dry-run=client`; **kubeconform** opcional (comando mantido na seção Validação se a ferramenta estiver instalada)
- [ ] Smoke pós-deploy com cluster real + Secret real + migrações: pod `Running`, `GET /health` e `GET /sources` (port-forward; sem `wget` dentro do Pod)

## DoD

- `kustomize build k8s/base` e `kustomize build k8s/overlays/production` produzem YAML válido.
- `kubectl apply --dry-run=client` passa no overlay de produção; kubeconform quando disponível.
- Deploy real revisado em PR: **um** Deployment API + Service + Secret/Config aplicados; pod estável; `/health` **200** dentro do cluster.
- Limite de recurso visível em `describe pod` coerente com a tabela de budget.
- README ou `docs/` com passos de migração/`DATABASE_URL` para operador.

## Validação

```bash
cd apps/ai-radar

kubectl kustomize k8s/base >/dev/null
kubectl kustomize k8s/overlays/production >/dev/null
just k8s-validate

# Opcional, se kubeconform estiver no PATH:
kubectl kustomize k8s/overlays/production | kubeconform -strict -summary -ignore-missing-schemas -

# Após deploy (tunnel kubectl configurado; Secret DATABASE_URL válido aplicado antes)
kubectl -n ai-radar get pods,svc
kubectl -n ai-radar port-forward svc/ai-radar-api 18080:8080
curl -fsS http://127.0.0.1:18080/health
curl -fsS -H 'X-Request-Id: smoke-001' http://127.0.0.1:18080/sources
```

## References

- `docs/AI-RADAR-DECISIONS.md` — budget ARM64, Postgres compartilhado
- **T-171** — onda 2 (CronJobs + demo completo)
- `.agents/skills/deploy-service/SKILL.md`
- `.agents/skills/operational-safety/SKILL.md`
- Depende de: **T-160** (API + DB + migrations aplicáveis ao schema `ai_radar`)
- Branch sugerida: `feat/T-174-ai-radar-k8s-baseline`
