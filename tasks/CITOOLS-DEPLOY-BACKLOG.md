# Cursor Queue — citools Deploy Program (T-344)

Epic master: [T-344-Program-citools-deploy-CI-closure-epic.md](2026/Q2/T-344-Program-citools-deploy-CI-closure-epic.md)

## Ordem recomendada

| # | ID | Fase | Entrega |
| -: | :- | :--- | :------ |
| **0** | **T-349** | **UX Jenkins** | Blue Ocean + Pipeline Stage View |
| 1 | **T-345** | CI closure | Branch protection `jenkins/citools` + webhook |
| 2 | **T-346** | Catálogo | `deploy-catalog.yaml` + `citools deploy list/plan/run` |
| 3 | **T-347** | Workers | Hetzner buildx + targets OCI/SSDNodes |
| 4 | **T-348** | Jenkins | Job `deploy-apps` parametrizado |

## Em andamento (CI platform — PR #394)

| # | ID | Tarefa | Status |
| -: | :- | :----- | :----- |
| 1 | **T-341** | Jenkins + Sonar + citools quality | 🏎️ PR #394 |
| 2 | **T-342** | Bump Sonar 26.6 + Jenkins 2.567 | 🏎️ live |
| 3 | **T-343** | Reverse proxy + security | 🏎️ live |

## Princípio

`apps/*/deploy.sh` **permanece**. citools orquestra; workers injetam env; Jenkins expõe UI.
