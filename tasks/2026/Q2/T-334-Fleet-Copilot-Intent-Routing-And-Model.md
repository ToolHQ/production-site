# T-334: Fleet Copilot — intent routing + qualidade de resposta

- **Status**: In Progress
- **Priority**: 🔼 High
- **Epic**: Fleet Copilot fase 2
- **Est**: 1d
- **Depends on**: T-332

## Problema (screenshot 2026-05-31)

- Gemma 3 4B em CPU repete a mesma frase genérica
- Preset fixo (`ssdnodes-health`) → contexto sempre disk/memory/load mesmo quando pergunta é meta (*"o que você faz?"*, *"quais hosts?"*)
- Sem routing: `custom` message usa preset default errado

## Entrega

- [x] **Intent classifier leve** (server-side, sem LLM):
  - `meta_capabilities` → resposta template + manifest (T-332)
  - `host_health` → disk/memory/load
  - `k8s_status` → pods/ingress/warnings
  - `ssh_audit` → ssh-recent
  - `fleet_compare` → fast-path métricas multi-host (T-333)
- [x] Override preset quando intent ≠ preset UI selecionado (server-side `resolve_intent`)
- [ ] A/B modelo: `qwen2.5:3b` vs `gemma3:4b` (latência + qualidade pt-BR)
- [x] Few-shot no system prompt (2–3 exemplos Q&A fleet ops)
- [x] Fallback: se resposta < 20 chars ou repete contexto → mensagem honesta *"modelo limitado; veja source pills"*

## Relacionado

- T-327 — loading UX (~2 min)
- T-324 — Hermes fase 2 (multi-turn opcional)

## DoD

- *"O que você consegue fazer?"* → lista capabilities + hosts (não só df)
- *"perguntei quais porra"* → lista hostnames (sem loop)
