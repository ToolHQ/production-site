# T-330: SSDNodes — hostname canônico (deprecar apelido "monstro")

- **Status**: Done (2026-05-31)
- **Priority**: High
- **Epic**: Fleet Copilot / Node Fleet
- **Estimation**: 2h

## Contexto

O host dedicado SSDNodes tem hostname real **`ssdnodes-6a12f10c9ef11`** (`hostname -f` @ 104.225.218.78).
O apelido **`ssdnodes-monstro`** era alias SSH ops informal e aparecia na UI do Fleet Copilot — confundia operadores.

## Entrega

- [x] UI Copilot: `ssdnodes-6a12f10c9ef11` em copy, presets e prompts
- [x] `external_nodes.json` + `registry.yaml`: `id` = hostname canônico
- [x] Regenerar manifest Prometheus (`ssdnodes-6a12f10c9ef11-exporter.yaml`)
- [x] Harness: fail se `ssdnodes-monstro` no bundle JS live
- [x] `ufw_manager`: host canônico + resolução SSH → alias legado
- [ ] **Backlog T-331**: `~/.ssh/config` — adicionar `Host ssdnodes-6a12f10c9ef11` e deprecar alias monstro

## Validação

```bash
bash scripts/harness/validate_fleet_copilot.sh
# UI JS: ok ssdnodes-6a12f10c9ef11, ok free of ssdnodes-monstro
curl -sS https://reports.dnor.io/assets/app.js | grep -c ssdnodes-monstro  # → 0
```

## Notas

- Scripts que fazem `ssh` continuam resolvendo `ssdnodes-6a12f10c9ef11` → `ssdnodes-monstro` até T-331.
- Preset ids (`ssdnodes-health`, etc.) permanecem — referem provider, não hostname.
