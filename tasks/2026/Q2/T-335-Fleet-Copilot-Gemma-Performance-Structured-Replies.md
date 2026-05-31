# T-335: Fleet Copilot — Gemma performance + respostas estruturadas

- **Status**: In Progress
- **Priority**: 🔼 High
- **Epic**: Fleet Copilot fase 2
- **Est**: 1d
- **Depends on**: T-332, T-334

## Problema

Gemma 3 4B em CPU no monstro:
- 1–3 min por pergunta; timeout Ollama = **180s** (`OLLAMA_TIMEOUT`)
- Respostas truncadas (*"Os"*) quando estoura o limite
- Perguntas operacionais simples (*"Como estão os recursos?"*) não precisam de LLM

## Entrega

- [x] Intent `fleet_resources` + resposta **estruturada** (`fleet-structured`) sem Ollama
- [x] Host health / k8s / SSH → parse `stdout` dos ops endpoints antes de chamar Gemma
- [x] `fleet_metrics_snapshot` no manifest para visão geral Prometheus
- [x] Fallback pós-Gemma: resposta curta/eco → structured ou aviso honesto
- [x] Gateway: `num_ctx` 4096, `num_predict` 384 (menos tokens = mais rápido)
- [ ] A/B `qwen2.5:3b` vs `gemma3:4b` (`FLEET_OLLAMA_MODEL` + doc)
- [ ] Warm-up Ollama no boot / keep_alive tuning

## DoD

- *"Como estão os recursos?"* → resposta em **<5s** com df/free + métricas Prometheus
- Gemma só para perguntas analíticas sem template (backlog)

## Relacionado

- T-334 — intent routing
- T-327 — loading UX (Gemma residual)
