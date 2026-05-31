# T-333: Fleet Copilot — multi-node (OCI + external fleet)

- **Status**: In Progress
- **Priority**: 🔼 High
- **Epic**: Fleet Copilot fase 2
- **Est**: 1–2d
- **Depends on**: T-332

## Problema

Copilot só analisa **dados coletados no SSDNodes** (host local + K8s local no mesmo metal). Operador quer perguntar sobre:

- `k8s-node-1`, `k8s-master` (OCI Ampere)
- `hetzner-cax21-helsinki`
- `ip-172-31-65-56` (honeypot AWS)
- Comparar disco/memória entre nós

## Arquitetura alvo

```
Pergunta → intent (host? cluster? compare?)
         → fetch contexto por fonte:
            - SSDNodes gateway (host + k8s local) — já existe
            - rs-observability-api live_overview + node_metrics — OCI
            - Prometheus node_exporter (via API interna) — externos
         → prompt compacto → Ollama
```

## Entrega

- [x] Presets novos ou modo livre com **seletor de nó** na UI (dropdown Node Fleet)
- [x] `@mention` ou autocomplete: `k8s-node-2`, `ssdnodes-6a12f10c9ef11`, … _(chips @host no composer)_
- [x] Proxy: mapear hostname → fonte de dados (gateway vs live API vs skip) — `targeted_oci_nodes` + `targeted_external_nodes`
- [x] Limites: max 3 nós por pergunta; truncar séries Prometheus
- [ ] Read-only — sem kubectl remoto cross-host (só dados já expostos)

## Fora de escopo v1

- SSH/exec em nós arbitrários
- LLM escolhendo endpoints (manter allowlist server-side)

## DoD

- *"Como está a memória do k8s-node-1?"* → resposta grounded com métrica live
- *"Compare disco SSDNodes vs hetzner builder"* → resumo dos dois (se dados existirem)
