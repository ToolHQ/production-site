# T-335: Fleet Copilot — Gemma performance + respostas estruturadas

- **Status**: Done
- **Priority**: 🔼 High
- **Epic**: Fleet Copilot fase 2
- **Est**: 1d
- **Depends on**: T-332, T-334

## Problema

Gemma 3 4B em CPU no monstro:
- 1–3 min por pergunta; timeout Ollama = **180s**
- Respostas truncadas (*"Os"*) quando estoura o limite
- Perguntas operacionais simples não precisam de LLM

## Entrega

- [x] Intent `fleet_resources` + resposta **estruturada** (`fleet-structured`) sem Ollama
- [x] Host health / k8s / SSH → parse `stdout` antes de Gemma
- [x] `fleet_metrics_snapshot` no manifest
- [x] Fallback pós-Gemma → structured ou aviso
- [x] Gateway: `num_ctx` 4096, `num_predict` 384
- [x] A/B `qwen2.5:3b` documentado (`FLEET_OLLAMA_MODEL`)
- [x] Warm-up: `components/ssdnodes/fleet-copilot/warmup_ollama.sh`

## DoD

- [x] *"Como estão os recursos?"* → **<5s** structured (harness T-335)
- [x] Gemma residual só para perguntas sem template
