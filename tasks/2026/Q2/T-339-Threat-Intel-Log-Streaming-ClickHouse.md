# T-339: Honeypot + SSDNodes — Threat Intel Log Streaming via ClickHouse (Fase 6)

**Epic:** Node Fleet v2 (Fase 6 - Threat Intelligence)
**Owner:** Antigravity
**Status:** BACKLOG

## Contexto
O monitor atual do honeypot AWS EC2 salva os logs localmente, o que gerou problemas de retenção e disco cheio (T-312). Além disso, a porta 22 do SSDNodes está recebendo brute force constante, que passamos a mitigar com Fail2Ban, mas sem visibilidade unificada.

## Objetivo
Centralizar e persistir a inteligência de ameaças no nosso cluster OCI (ClickHouse), permitindo:
- Banimento ativo local (Fail2Ban resolvido).
- Ingestão contínua de metadados de ataque (IP, geo, serviço, horário).
- Expurgar de forma segura os logs locais (resolvendo o T-312).

## Escopo (To Do)
- [ ] Subir um pipeline de ingestão (`vector` ou `fluent-bit`) em ambas as máquinas (EC2 e SSDNodes) via Tailscale.
- [ ] Criar a tabela `threat_intel_events` no ClickHouse (`coroot` ou banco novo).
- [ ] Redirecionar os componentes da UI (`HoneypotThreatsCard`) para ler do ClickHouse.
- [ ] Configurar cron de purge rigoroso nas origens.
