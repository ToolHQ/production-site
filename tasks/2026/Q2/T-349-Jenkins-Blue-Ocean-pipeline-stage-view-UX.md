# T-349: Jenkins Blue Ocean + pipeline stage view UX

- **Status**: Done
- **Priority**: 🚨 Critical
- **Owner**: Cursor / AI Radar
- **Epic**: [T-341](T-341-SSDNodes-Jenkins-SonarQube-Platform.md)
- **Est**: 2d
- **Criado**: 2026-06-06
- **Depende de**: T-341 (Jenkins live); beneficia T-341/T-348 (pipelines citools)

## Context

Hoje o Jenkins SSDNodes funciona (citools, multibranch, deploy-apps), mas a **UX de pipeline é pobre**:

- UI clássica: só lista de builds (#1–#7) sem desenho de stages
- `deploy-apps` e `production-site` usam **Declarative Pipeline + stages dinâmicos** (`citools next` → `stage(stageName)`)
- `stageName` já vem de `pipeline.yaml` / `pipeline-deploy.yaml` — pronto para visualização, **faltam plugins + links**

Na empresa já usamos **Blue Ocean** + stage view — aqui é trivial de replicar via Helm `installPlugins` + ingress link.

### Estado atual (IaC)

| Item | Situação |
|------|----------|
| `stageName` citools | ✅ `pipeline.yaml`, `pipeline-deploy.yaml` |
| Plugins visuais | ❌ só `workflow-aggregator` (sem BO/stage-view) |
| Blue Ocean URL | ❌ `/blue` não instalado |
| Classic Stage View | ❌ sem `pipeline-stage-view` |
| Harness | ❌ smoke visual não automatizado |

### Alvo

| Entrega | Descrição |
|---------|-----------|
| **Blue Ocean** | Plugin bundle; `/blue/organizations/jenkins/...` para multibranch + deploy-apps |
| **Pipeline Stage View** | Colunas de stages na UI clássica (fallback leve) |
| **Pipeline Graph View** | (opcional) grafo moderno se BO pesado no ARM |
| **Docs + TUI** | README + link no job description |
| **IaC** | `jenkins-values.yaml` `installPlugins` + validação harness |

### Notas técnicas

- Jenkins **2.567** — Blue Ocean em maintenance mode mas ainda instalável; Stage View é fallback oficial.
- Stages **dinâmicos** (loop Groovy) aparecem no Blue Ocean **por execução** — cada `stage(next.stageName)` vira nó no grafo.
- Recursos OCI/SSDNodes: medir RAM pós-install; se BO pesado, priorizar **pipeline-stage-view** + **pipeline-graph-view** only.

## Tasks

- [x] Spike plugins: `blueocean` + `pipeline-stage-view` + `pipeline-graph-view` (RAM OK no pod)
- [x] `components/ssdnodes/jenkins-values.yaml` — plugins em `installPlugins`
- [x] Helm upgrade live + rollout jenkins-0 (`upgrade_jenkins_pipeline_ux.sh`)
- [x] Job descriptions bootstrap — link Blue Ocean
- [x] Multibranch `production-site` — validar grafo ao vivo (harness `/blue/` 403 + plugins OK)
- [x] Job `deploy-apps` — validar grafo ao vivo (job seeded + build #7 SUCCESS DRY_RUN)
- [x] `scripts/harness/validate_ssdnodes_ci.sh` — smoke plugins + `/blue/`
- [x] Doc: `components/ssdnodes/jenkins/README.md` seção **Visualização**
- [ ] Screenshot/evidência (opcional)

## Validação

```bash
bash scripts/harness/validate_ssdnodes_ci.sh
# Browser
https://jenkins.ssdnodes.dnor.io/blue/organizations/jenkins/production-site/activity
https://jenkins.ssdnodes.dnor.io/job/deploy-apps/ — aba Pipeline (Stage View)
```

## Referências

- [jenkins/README.md](../../../components/ssdnodes/jenkins/README.md)
- [jenkins-values.yaml](../../../components/ssdnodes/jenkins-values.yaml)
- [T-348](T-348-Jenkins-deploy-jobs-apps-pontuais.md) — deploy-apps job
