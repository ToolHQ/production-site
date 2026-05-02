# T-171: AI Radar — Kubernetes Operação Leve (onda 2 — CronJobs)

- **Status**: Done
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp / Infra
- **Estimation**: 1d
- **Opened**: 2026-05-01

## Context

**Onda 2** do Kubernetes: estende o **baseline** entregue em **T-174** (API + Service + Secret + imagem Nexus já validados no cluster).

Aqui entram **CronJobs** substituindo workers 24/7, quotas adicionais se o cluster exigir, e smoke **demo-ready** (incl. jobs derivados dos schedules do `AI-RADAR-DECISIONS.md`). Não repetir trabalho já feito na Deployment/Service baseline — apenas referenciar e evoluir o mesmo `apps/ai-radar/k8s/` com novos manifests.

Seguir skill `deploy-service` e `operational-safety` do `AGENTS.md`. Sem tocar Postgres/Nexus/Longhorn como workloads a migrar — só consumo via Secret.

Este épico **fecha o MVP demo-ready no cluster** no sentido pipeline agendado (collect → … → digest), assumindo CLI/subcomandos estáveis conforme épicos anteriores.

## Tasks

- [x] CronJob **`ai-radar-collect`** em `k8s/base/cronjobs/cronjob-collect.yaml` (`*/30 * * * *`), imagem **`my-site-ai-radar-cli`**, `args: [collect]` — **merge incremental** (extract/score/digest quando T-165/T-166/T-169 existirem na CLI)
- [x] `concurrencyPolicy: Forbid`, `successfulJobsHistoryLimit: 3`, `failedJobsHistoryLimit: 5`, `activeDeadlineSeconds: 600`
- [x] Resources CronJob: `req cpu=50m mem=128Mi / lim cpu=500m mem=512Mi`
- [x] securityContext nos Jobs: `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, drop ALL caps
- [x] `nodeSelector: kubernetes.io/arch: arm64`
- [x] Reutilizar mesmo `Namespace`/`ServiceAccount`/padrão `imagePullSecrets` já aplicados na **T-174**; `kustomization.yaml` + overlay `images` para CLI
- [x] `deploy.sh`: build/push **API + CLI** com o mesmo `TAG_VERSION`; `sed` em ambas as referências de imagem antes do `kubectl apply`
- [x] `Dockerfile.cli` alinhado ao cross-build do `Dockerfile.api` (sem `exec format error` ARM64)
- [ ] CronJobs `extract` / `score` / `digest-*` — dependem **T-165**, **T-166**, **T-169**
- [ ] Opcional: atalho **TUI** (`oci-k8s-cluster/k8s_ops_menu.sh`) — entrada mínima (logs/status namespace `ai-radar`)
- [x] Lint manifests (kubeconform) incluindo cron manifests — CI `yaml-quality` + `just k8s-validate` (kubeconform opcional no PATH)
- [x] Smoke em cluster: `kubectl create job --from=cronjob/ai-radar-collect …` + logs (job manual OK)

## DoD

- `kustomize build k8s/overlays/production` inclui baseline **T-174** + CronJobs válidos.
- `kubeconform` passa.
- Deploy revisado em PR → CronJobs listados em `kubectl -n ai-radar get cronjobs`; job ad-hoc a partir de um CronJob executa até completar ou falhar com erro de **negócio** (feed/LLM), não infraestrutura.
- `/health` da API segue OK (sem regressão).
- Logs de job rastreáveis (baseline para T-172 enriquecer com `job_id`).

## Validação

```bash
cd apps/ai-radar
kustomize build k8s/overlays/production | kubeconform -strict -summary
kustomize build k8s/overlays/production | kubectl apply --dry-run=client -f -

kubectl -n ai-radar get deploy,cronjobs
kubectl -n ai-radar create job --from=cronjob/ai-radar-collect collect-test-$(date +%s)
kubectl -n ai-radar logs job/<job-name>
```

## References

- `docs/AI-RADAR-DECISIONS.md` — schedules e budget CronJob
- `docs/AI-RADAR-ROADMAP.md` — Fase 13
- **T-174** — baseline API (pré-requisito)
- `.agents/skills/deploy-service/SKILL.md`
- `.agents/skills/operational-safety/SKILL.md`
- `AGENTS.md` — Stability First, GitFlow obrigatório
- Depende de: **T-174** + **T-169** — digest CronJobs exigem o gerador (**T-169**); jobs `collect` / `extract` / `score` tornam-se operacionais à medida que **T-161**, **T-165**, **T-166** forem mergeados (entrega incremental).
- Branch sugerida: `feat/T-171-ai-radar-k8s-cronjobs`
