# T-332: Fleet Copilot — manifesto de fleet no contexto LLM

- **Status**: Done
- **Priority**: 🔼 High
- **Epic**: Fleet Copilot fase 2
- **Est**: 4h
- **Depends on**: T-315 MVP

## Problema

Operador pergunta *"quais hosts você analisa?"* e o Gemma repete disco/memória — o **contexto JSON não inclui inventário de nós**. O system prompt não lista escopo.

Hoje `collect_context()` só busca 1–4 endpoints do gateway SSDNodes (`df`, `free`, `uptime`) — zero metadados de fleet OCI/Hetzner/AWS.

## Entrega

- [x] Server-side: injetar `fleet_manifest` no contexto antes do Ollama:
  - Nós OCI-K8s (`/api/live/overview` → names, cluster, IP, role)
  - Externos (`external_nodes.json` / registry): `ssdnodes-6a12f10c9ef11`, hetzner-cax21, aws-ec2-fleet-01
  - Escopo explícito: *gateway read-only roda em SSDNodes; métricas OCI vêm do Cluster Pulse*
- [x] System prompt atualizado: *"Hosts disponíveis: … Responda sobre qual host o operador perguntou; se ambíguo, liste os hosts e peça clarificação."*
- [x] Harness: pergunta fixture *"quais hosts?"* → fast-path `fleet-manifest` (14/14 harness)

## Arquivos

- `apps/rs-observability-api/src/fleet_copilot.rs` — `collect_fleet_manifest()`
- `apps/fleet-ops-gateway/src/main.rs` — system prompt (ou só proxy)

## DoD

- Chat responde corretamente *"quais hosts você cobre?"* sem repetir só df
