# 📋 Copilot/VSCode Queue

> **Fila de trabalho exclusiva do GitHub Copilot (VSCode).**
> O `KANBAN.md` continua como **única fonte de verdade** para tarefas T-ID.
> Este arquivo funciona como _sprint board_ de sessão do Copilot — não duplica, apenas filtra e complementa.

## Regras de Uso

- **Copilot** só trabalha em tarefas onde `Owner` contém `Copilot/VSCode` no `KANBAN.md`, ou em micro-tasks listadas aqui.
- **Cursor** usa `tasks/CURSOR-QUEUE.md` e worktree `~/production-site-cursor` (owner **AI Radar** no KANBAN).
- **Cursor / Antigravity** não devem pegar tarefas com `Owner: Copilot/VSCode`.
- Micro-tasks (< 30 min, sem branch) ficam apenas aqui. Ao completar, marcam como `[x]` — sem mover para KANBAN.
- Tarefas T-ID exigem branch em `production-site-copilot` → PR → merge.

## 🏎️ Em Andamento (sessão atual)

_Nada em andamento — aguardando próxima task._

## 📋 Próximas (Copilot/VSCode)

> Referenciar T-IDs do KANBAN.md (com `Owner: Copilot/VSCode`) ou micro-tasks.

| ID / Ref                                                          | Tarefa                                                                                                                                                                                                                        | Prioridade      |
| :---------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :-------------- |
| ~~[T-293](2026/Q2/T-293-Node3-IOWait-Saturation-Containment.md)~~ | ~~Conter saturação de I/O wait no k8s-node-3 (ClickHouse/Prometheus)~~ ✅ Done (merge_with_ttl_timeout=86400; wa: 80%→0%; 2026-05-25)                                                                                         | ~~🚨 Critical~~ |
| ~~[T-303](2026/Q2/T-303-SSDNodes-Dashboard-Kubecost-HTTPS.md)~~   | ~~**SSDNodes — Kubernetes Dashboard + Kubecost HTTPS**~~ ✅ Done (HTTP 200 ambos; TLS R12/R13; PR #352; 2026-05-26)                                                                                                           | ~~🔵 Medium~~   |
| ~~—~~                                                             | ~~Finalizar cutover de CI para self-hosted Hetzner (runner + variable + smoke)~~ ✅ Done (PR #443 — port fix + migration fix + test fix; CI green; 2026-06-08) | ~~🔼 High~~     |
| ~~—~~                                                             | ~~**CodeQL no ssdnodes-monstro**: instalar runner x86_64 + mover `codeql.yml` de `ubuntu-latest` → `[self-hosted, Linux, X64, ssdnodes]`. Diagnosticar falhas JS/Python no próprio hardware.~~ ✅ PR #351 merged (2026-05-25) | ~~🔵 Medium~~   |
| Radar (futuro)                                                    | Plataforma AppSec Open Source (roadmap faseado, separado das demandas principais) -> `docs/open-source-appsec-roadmap.md`                                                                                                     | 🔽 Low          |
| ~~—~~                                                             | ~~Monitorar estabilidade do cluster~~ ✅ Done (4 nós Ready, 86 pods Running, MinIO rollback stuck corrigido; 2026-06-08)                                                                                                       | ~~🔽 Low~~      |

## 🔬 Micro-Tasks (sem T-ID, sem PR)

> Itens rápidos de uma sessão. Ao concluir, marcar `[x]` aqui e commitá-los na branch corrente (se houver).

- [x] `kubectl delete pods -n kube-system --field-selector=status.phase=Failed` — limpar evicted
- [x] Deletar pods stale ContainerStatusUnknown (ai-radar, hubble-relay, failed-pod-cleaner)
- [x] Fix CronJob `failed-pod-cleaner` image: `bitnami/kubectl:1.31` → `registry.k8s.io/kubectl:v1.28.0`
- [x] T-263: Brand header (icon, title, subtitle, bg-glow, favicon, footer) — PR #262 merged
- [x] Fix max-width:220px em `td` quebrando column resize — PR #264 merged
- [x] Fix CONV ID substring(0,8) hardcoded no JS + IP substring(0,15) + click-to-filter — tag 1779188533
- [x] Audit completo Agent Meter (2025-07-14): todas abas, filtros, endpoints — criadas T-276 a T-281
- [x] T-282: Fix Top MCP Servers — `AND tool_name != 'llm_chat'` — PR #271 merged ✅
- [x] T-277: Top Tasks → Top Conversations — `conversation_id`, click-to-filter — PR #271 merged ✅
- [x] T-278: Remover link /metrics morto do footer — PR #271 merged ✅
- [x] T-279: formatDuration() humanizada (ms/s/min) — PR #271 merged ✅
- [x] Fix kubecost nginx-conf ConfigMap deletado acidentalmente — PR #274 merged ✅
- [x] Mitigar flapping no k8s-master: desativado `pleg-monitor.service` (reiniciava containerd/kubelet a cada 60s)
- [x] agent-meter low-cost polish: pausar polling com aba oculta, reduzir fetch em Events, corrigir `loadEvents()` → `renderEventsTab()`, `imagePullPolicy: IfNotPresent`, dedupe `RUST_LOG`
- [x] agent-meter DB perf pass: reescrever Top Tools com CTE (sem subquery correlacionada) + índices compostos focados em filtros de reports
- [x] CI cost cutover: self-hosted runner Hetzner ativo (`hetzner-ci-01`, ARM64) + `CI_RUNNER_LABELS` aplicado + PR #284 merged

## ✅ Concluídas (histórico recente)

| ID / Ref                                                                          | Tarefa                                                                          | Data       |
| :-------------------------------------------------------------------------------- | :------------------------------------------------------------------------------ | :--------- |
| [T-292](2026/Q2/T-292-Node-Fleet-External-Node-Identity-And-Hardware-Metadata.md) | Node Fleet — identidade de nós externos + IP/arquitetura/SO + validação ao vivo | 2026-05-24 |
| [T-280](2026/Q2/T-280-Agent-Meter-Model-Filter-Em-Reports.md)                     | agent-meter — filtro model global aplicado em reports (backend + dashboard)     | 2026-05-23 |
| [T-281](2026/Q2/T-281-Agent-Meter-Sort-Colunas-Reports.md)                        | agent-meter — sort interativo em colunas dos reports                            | 2026-05-23 |
| [T-203](2026/Q2/T-203-Node-Fleet-Tooltip-Fixed-Positioning.md)                    | Node Fleet Tooltip Fixed Positioning (TooltipWrapper)                           | 2026-05-17 |
| [T-201](2026/Q2/T-201-Node-Fleet-Real-Machine-Metrics-Prometheus.md)              | Node Fleet Real Machine Metrics via Prometheus                                  | 2026-05-17 |
| [T-200](2026/Q2/T-200-Node-Fleet-Panel-Layout-Polish.md)                          | Node Fleet Panel Layout Polish                                                  | 2026-05-17 |
| [T-193](2026/Q2/T-193-Master-rootfs-cleanup-BuildKit-cache-legado-MinIO.md)       | Master rootfs cleanup + hook prune pós-build                                    | 2026-05-16 |
| [T-282](2026/Q2/T-282-Agent-Meter-Top-MCP-Servers-Semantic-Fix.md)                | agent-meter T-282/277/278/279 — audit fixes (PR #271)                           | 2026-05-19 |
| —                                                                                 | fix(kubecost): nginx-conf ConfigMap deletado acidentalmente (PR #274)           | 2026-05-20 |
| `feat/copilot-infra-backlog`                                                      | Triage infra/estabilidade: T-196/197/198 + KANBAN                               | 2026-05-16 |
| `feat/copilot-task-structure`                                                     | Setup inicial: worktree + queue + loop workflow + PR                            | 2026-05-16 |
