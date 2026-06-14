# T-341: Tailscale Ingress Manager

**Epic:** Observability & Resilience (Q2 2026)
**Owner:** Antigravity
**Status:** DONE

## Contexto
Múltiplos serviços internos (ClickHouse, Grafana, etc.) precisam ser expostos via ingress com restrição Tailscale. O processo manual de criar manifests, aplicar no cluster e configurar DNS no GoDaddy é repetitivo e propenso a erros.

## Objetivo
Criar um script unificado (`manage_tailscale_ingress.sh`) que:
- Cria/deleta ingresses com whitelist Tailscale automaticamente
- Gera manifests versionados em `components/observability/`
- Integra com GoDaddy API para DNS automation
- Valida conectividade via Tailscale
- Lista todos os ingresses restritos

## Escopo
- [x] Script `manage_tailscale_ingress.sh` com comandos: create, delete, list, validate, dns
- [x] Manifests gerados em `components/observability/<service>-ingress.yaml`
- [x] Integração com GoDaddy API (via `.env.godaddy`)
- [x] Validação automática via Tailscale IP
- [x] Integração com TUI (`k8s_ops_menu.sh`)
- [x] Task no KANBAN.md

## Comandos
```bash
# Criar novo ingress
./scripts/manage_tailscale_ingress.sh create grafana grafana-service 3000 --namespace monitoring

# Listar todos
./scripts/manage_tailscale_ingress.sh list

# Validar
./scripts/manage_tailscale_ingress.sh validate clickhouse

# DNS via GoDaddy
./scripts/manage_tailscale_ingress.sh dns grafana 150.136.67.52 --dry-run
```

## Padrão de Segurança
- Whitelist: `100.64.0.0/10` (Tailscale IPs only)
- DNS público (GoDaddy) → acesso restrito no L7 (nginx whitelist)
- Serviços podem ter auth adicional (ex: ClickHouse `X-ClickHouse-User/Key`)
