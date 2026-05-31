# T-327: Fleet Copilot — UX de carregamento da inferência (Gemma lento)

- **Status**: Done
- **Priority**: 🔼 High
- **Owner**: Cursor / AI Radar
- **Epic**: Fleet Copilot (T-315)
- **Est**: 4h
- **Depends on**: T-323
- **Blocks**: Nenhum

## Context

Primeiro token do Gemma 3 4B no monstro pode levar **1–3 minutos**. Operadores interpretam como travamento ou resposta cortada.

## Escopo

- [x] Fase `infer`: copy após 45s com elapsed + hint ~3 min
- [x] Progress bar indeterminada ou elapsed + hint após 30s / 60s
- [x] Desabilitar double-submit no composer
- [x] `GET /api/fleet/copilot/status` — gateway reachability + modelo + structured-first

## Critérios de aceite

- [x] Usuário nunca vê tela vazia >10s sem feedback textual
- [x] Cancelar consulta continua funcionando

## Referências

- [T-323](T-323-Fleet-Copilot-UI-Reports.md)
- `web-v2/src/hooks/useFleetChat.ts`
