# T-174: AI Radar — Kubernetes Baseline (primeiro deploy API)

- **Status**: Backlog
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp / Infra
- **Estimation**: 4h
- **Opened**: 2026-05-01

## Context

**Onda 1** do deploy no cluster: colocar apenas a **API** (`ai-radar-api`) no OCI ARM64 com Postgres compartilhado, **antes** de digest/CronJobs completos. Objetivo é **validar incrementalmente** pull de imagem Nexus, probes, limites reais, `DATABASE_URL`, migrações contra o banco de produção e roteamento interno — sem esperar T-169/T-171.

Seguir `deploy-service` e `operational-safety` (`AGENTS.md`). Não alterar workloads stateful críticos (Postgres primário, Nexus, Longhorn).

**T-171** continua como **onda 2** (CronJobs, quotas adicionais, smoke completo demo-ready).

## Tasks

- [ ] `apps/ai-radar/k8s/base/namespace.yaml` (ou `kustomization` com `namespace:`) — namespace dedicado `ai-radar`
- [ ] `apps/ai-radar/k8s/base/serviceaccount.yaml` — SA dedicada, sem RBAC cluster-wide desnecessário
- [ ] `apps/ai-radar/k8s/base/deployment-api.yaml` — `replicas: 1`, containers: `ai-radar-api`, `securityContext` endurecido (`runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, capabilities drop ALL), probes `liveness`/`readiness`/`startup` em `GET /health`, resources alinhados a `AI-RADAR-DECISIONS.md` (`req` 25m/64Mi, `lim` 250m/256Mi)
- [ ] `apps/ai-radar/k8s/base/service.yaml` — ClusterIP :8080 → pods da API
- [ ] `apps/ai-radar/k8s/base/configmap.yaml` — apenas envs não secretas (`AI_RADAR_LOG_LEVEL`, placeholders de feature flags se já existirem no código)
- [ ] `apps/ai-radar/k8s/base/secret.yaml` — **template** (sem valores reais): chave `DATABASE_URL` com placeholder; documentar preenchimento via SealedSecrets/SOPS/External Secrets conforme padrão do cluster (**incluir `?options=-csearch_path%3Dpublic`** na URL, igual `.env.example`)
- [ ] Opcional recomendado: `Job`/`initContainer` documentado para **`sqlx migrate run`** one-shot na primeira subida (ou runbook `kubectl` + `migrate` a partir de imagem debug — escolher uma e documentar em `apps/ai-radar/README.md`)
- [ ] `imagePullSecrets` referenciando Nexus (mesmo padrão dos outros serviços ARM64 do repo)
- [ ] `apps/ai-radar/k8s/base/kustomization.yaml` + `apps/ai-radar/k8s/overlays/production/kustomization.yaml` (patch imagem/tag Nexus, `newName`/`newTag`)
- [ ] Integração com `./deploy.sh` ou script alinhado à skill `deploy-service` (build arm64, push, `kubectl apply`/Kustomize)
- [ ] Lint: `kustomize build ... | kubeconform` (ou equivalente já usado no repo)
- [ ] Smoke pós-merge: pod `Running`, `GET /health` OK (exec/wget ou port-forward), smoke mínimo **`GET /sources`** (pode retornar lista vazia) contra o Postgres real

## DoD

- `kustomize build k8s/base` e `kustomize build k8s/overlays/production` produzem YAML válido.
- `kubeconform` (ou ferramenta do projeto) passa.
- `kubectl apply --dry-run=client` passa no overlay de produção.
- Deploy real revisado em PR: **um** Deployment API + Service + Secret/Config aplicados; pod estável; `/health` **200** dentro do cluster.
- Limite de recurso visível em `describe pod` coerente com a tabela de budget.
- README ou `docs/` com passos de migração/`DATABASE_URL` para operador.

## Validação

```bash
cd apps/ai-radar
kustomize build k8s/base | kubeconform -strict -summary
kustomize build k8s/overlays/production | kubectl apply --dry-run=client -f -

# Após deploy (com tunnel kubectl configurado)
kubectl -n ai-radar get pods,svc
kubectl -n ai-radar exec deploy/ai-radar-api -- wget -qO- http://127.0.0.1:8080/health
# smoke opcional: port-forward e curl /sources
```

## References

- `docs/AI-RADAR-DECISIONS.md` — budget ARM64, Postgres compartilhado
- **T-171** — onda 2 (CronJobs + demo completo)
- `.agents/skills/deploy-service/SKILL.md`
- `.agents/skills/operational-safety/SKILL.md`
- Depende de: **T-160** (API + DB + migrations aplicáveis ao schema `ai_radar`)
- Branch sugerida: `feat/T-174-ai-radar-k8s-baseline`
