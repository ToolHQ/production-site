# T-171: AI Radar — Kubernetes Operação Leve

- **Status**: Backlog
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp / Infra
- **Estimation**: 1d
- **Opened**: 2026-05-01

## Context

Deploy do AI Radar no cluster OCI ARM64 com **resource budget conservador** (cluster 1 vCPU/6GB por node). Padrão Kustomize (`base/` + `overlays/production/`), CronJobs em vez de workers 24/7, securityContext hardenado, integração com Nexus para image pull.

**Importante**: seguir skill `deploy-service` e `operational-safety` do `AGENTS.md`. Nunca tocar workloads stateful críticos (Postgres, Nexus, Longhorn). Usar Postgres existente via Secret (DATABASE_URL).

Este é o épico que **fecha o MVP demo-ready** no cluster real.

## Tasks

- [ ] `apps/ai-radar/k8s/base/deployment.yaml` (API): replicas=1, securityContext hardenado, probes (liveness/readiness/startup em `/health`), resources `req cpu=25m mem=64Mi / lim cpu=250m mem=256Mi`
- [ ] `apps/ai-radar/k8s/base/service.yaml` ClusterIP porta 8080
- [ ] `apps/ai-radar/k8s/base/configmap.yaml` (envs não-sensíveis: log_level, schedules, max_*, base_url)
- [ ] `apps/ai-radar/k8s/base/secret.yaml` template (DATABASE_URL, OPENROUTER_API_KEY, GITHUB_TOKEN) — **valores reais via SealedSecrets/SOPS conforme padrão do cluster**
- [ ] `apps/ai-radar/k8s/base/serviceaccount.yaml` SA dedicada sem permissões cluster
- [ ] CronJobs em `apps/ai-radar/k8s/base/cronjobs/`: collect (`*/30 * * * *`), extract (`15,45 * * * *`), score (`5 * * * *`), digest-daily (`0 6 * * *`), digest-weekly (`0 7 * * 1`)
- [ ] `concurrencyPolicy: Forbid`, `successfulJobsHistoryLimit: 3`, `failedJobsHistoryLimit: 5`, `activeDeadlineSeconds: 600`
- [ ] Resources cron: `req cpu=50m mem=128Mi / lim cpu=500m mem=512Mi`
- [ ] securityContext: `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, drop ALL capabilities
- [ ] `nodeSelector: kubernetes.io/arch: arm64` (opcional, default cluster)
- [ ] `imagePullSecrets` apontando para Nexus
- [ ] `kustomization.yaml` em base + overlay `production` com patch de imagens (Nexus tag)
- [ ] Namespace dedicado `ai-radar` + ResourceQuota se cluster usa
- [ ] Lint manifests com `kubeconform`/`kubeval` (CI)
- [ ] Integração com `deploy.sh` ou skill `deploy-service`
- [ ] Smoke deploy no cluster: pods Running, `/health` acessível via Service interno

## DoD

- `kustomize build k8s/base` produz YAML válido.
- `kubeconform` passa sem erros.
- `kubectl apply --dry-run=client` passa.
- Deploy real (PR review) → pods Running, dentro dos limites de recurso.
- CronJobs rodam com `kubectl create job --from=cronjob/...` ad-hoc.
- `/health` responde via Service.
- Logs aparecem em `kubectl logs`.
- Sem warning de quota / scheduling.

## Validação

```bash
cd apps/ai-radar
kustomize build k8s/base | kubeconform -strict -summary
kustomize build k8s/overlays/production | kubectl apply --dry-run=client -f -

# Deploy real (após PR aprovado)
./deploy.sh ai-radar  # ou seguindo .agents/skills/deploy-service/SKILL.md

kubectl -n ai-radar get pods,cronjobs
kubectl -n ai-radar describe pod <api-pod> | grep -A2 -E 'Limits|Requests'
kubectl -n ai-radar exec <api-pod> -- wget -qO- localhost:8080/health
kubectl -n ai-radar create job --from=cronjob/ai-radar-collect collect-test-1
kubectl -n ai-radar logs job/collect-test-1
```

## References

- `docs/AI-RADAR-DECISIONS.md` — schedules, budget detalhado
- `docs/AI-RADAR-ROADMAP.md` — Fase 13
- `.agents/skills/deploy-service/SKILL.md`
- `.agents/skills/operational-safety/SKILL.md`
- `AGENTS.md` — Stability First, GitFlow obrigatório
- Depende de: **T-169**
- Branch sugerida: `feat/T-171-ai-radar-k8s-deployment`
