# T-334: Fleet Copilot — intent routing + qualidade de resposta

- **Status**: Done
- **Priority**: 🔼 High
- **Epic**: Fleet Copilot fase 2
- **Est**: 1d
- **Depends on**: T-332

## Problema (screenshot 2026-05-31)

- Gemma 3 4B em CPU repete a mesma frase genérica
- Preset fixo (`ssdnodes-health`) → contexto sempre disk/memory/load mesmo quando pergunta é meta
- Sem routing: `custom` message usa preset default errado

## Entrega

- [x] **Intent classifier leve** (server-side, sem LLM)
- [x] Override preset quando intent ≠ preset UI (server-side `resolve_intent`)
- [x] A/B modelo documentado: `FLEET_OLLAMA_MODEL` / `qwen2.5:3b` vs `gemma3:4b` — ver README fleet-copilot
- [x] Few-shot no system prompt
- [x] Fallback: resposta curta/eco → structured ou aviso honesto

## DoD

- [x] *"O que você consegue fazer?"* → lista capabilities + hosts
- [x] Meta / recursos / compare sem loop Gemma
