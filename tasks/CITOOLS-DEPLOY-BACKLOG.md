# Cursor Queue — citools Deploy Program (T-344)

Epic master: [T-344-Program-citools-deploy-CI-closure-epic.md](2026/Q2/T-344-Program-citools-deploy-CI-closure-epic.md)

## Ordem recomendada

| # | ID | Fase | Entrega | Status |
| -: | :- | :--- | :------ | :----- |
| **0** | **T-349** | **UX Jenkins** | Blue Ocean + Pipeline Stage View | ✅ |
| 1 | **T-345** | CI closure | Branch protection `jenkins/citools` + webhook | ✅ |
| 2 | **T-342** | CI bump | Sonar 26.6 + Jenkins 2.567 JDK25 | 🏎️ |
| 3 | **T-343** | Security | Reverse proxy + hardening | 🏎️ |
| 4 | **T-346** | Catálogo | `deploy-catalog.yaml` + `citools deploy list/plan/run` | 📋 |
| 5 | **T-347** | Workers | Hetzner buildx + targets OCI/SSDNodes | 📋 |
| 6 | **T-348** | Jenkins | Job `deploy-apps` parametrizado | 📋 |

## Epic paralelo: SSDNodes n8n (2026-06-09)

| # | ID | Tarefa | Depende |
| -: | :- | :----- | :------ |
| 1 | **T-361** | n8n Docker + TLS + auth | T-343 recomendado (proxy patterns) |
| 2 | **T-362** | Email automation research/specs | T-361 |

## Princípio

`apps/*/deploy.sh` **permanece**. citools orquestra; workers injetam env; Jenkins expõe UI.
