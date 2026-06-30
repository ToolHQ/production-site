# T-362: agent-meter Setup Page

## Problem

Hoje, para usar o agent-meter-proxy, clientes precisam:
1. Baixar o binário manualmente
2. Rodar `agent-meter-proxy setup` no terminal
3. Configurar proxy manualmente no IDE

Isso é impraticável para um produto SaaS. Clientes esperam uma página de setup simples.

## Solution

Criar página `/setup` no agent-meter com:
- Download do certificado CA (.pem)
- Instruções por OS (Windows/Mac/Linux)
- Botão "Instalar automaticamente" para cada SO

## Scope

### Must Have
- [ ] Rota `/setup` no collector
- [ ] Página HTML com download do CA
- [ ] Instruções para Windows (PowerShell)
- [ ] Instruções para Mac (Keychain)
- [ ] Instruções para Linux (update-ca-certificates)

### Nice to Have
- [ ] Botão 1-click install via PowerShell remoto
- [ ] Detecção automática de SO
- [ ] Script de setup para WSL

## Technical

- Nova rota em `routes/setup.rs`
- Servir certificado CA via endpoint `/api/setup/ca-cert`
- Página HTML com JavaScript para detecção de SO

## Files

- `apps/agent-meter/crates/collector/src/routes/setup.rs` (novo)
- `apps/agent-meter/crates/collector/src/routes/mod.rs` (adicionar rota)
- `apps/agent-meter/crates/collector/src/templates/setup.html` (novo)

## Estimation

3h

## Dependencies

- T-319 (multi-tenant) — não bloqueia, mas seria ideal ter auth antes de expor /setup público
