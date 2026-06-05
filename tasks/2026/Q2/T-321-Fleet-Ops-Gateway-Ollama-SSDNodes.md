# T-321: Fleet Copilot — Ops Gateway + Ollama no SSDNodes

- **Status**: Done (MVP 2026-05-31 — Ollama + gateway :18443 + IaC; backlog: kubeconfig view-only dedicado, usuário OS)
- **Priority**: 🔼 High
- **Owner**: Cursor / AI Radar
- **Epic**: Fleet Copilot / SSDNodes
- **Est**: 3d (321a–321e)
- **Depends on**: T-320 (gate: 320a, 320b, 320e Done)
- **Blocks**: T-322

## Context

Backend **read-only** no `ssdnodes-monstro`:

1. **Ollama** — inferência local Gemma/Qwen (zero custo variável)
2. **fleet-ops-gateway** — serviço Rust (ou binário mínimo) que executa **somente** comandos hardcoded; o LLM **nunca** monta shell livre

Princípio de segurança:

> **Execução determinística no gateway; LLM só interpreta JSON já coletado.**

Hermes Agent **não** faz parte deste epic (ver T-324).

---

## T-321a — Spike capacidade RAM/CPU com workloads existentes

- **Est**: 4h

### Objetivo

Medir headroom antes de fixar modelo Ollama.

### Checklist

- [ ] Snapshot baseline com stack completa rodando:
  ```bash
  ssh ssdnodes-monstro "free -h; kubectl top nodes 2>/dev/null; kubectl top pods -A 2>/dev/null | head -20"
  ```
- [ ] Instalar Ollama temporário (sem systemd permanente)
- [ ] Testar modelos (pull + 10 prompts fixos, medir latência p50/p95):
  - [ ] `gemma3:12b` (preferido se couber)
  - [ ] `qwen2.5:14b` (fallback tool-friendly)
  - [ ] `gemma2:9b` (fallback leve — chat only)
- [ ] Durante spike: monitorar `free -h`, load average, impacto em MinIO latency
- [ ] Documentar modelo escolhido + `OLLAMA_NUM_PARALLEL=1`, `OLLAMA_MAX_LOADED_MODELS=1`

### DoD

- Tabela comparativa RAM/latência no corpo desta task (seção Evidência)
- Decisão de modelo registrada

### Evidência spike (2026-05-30)

| Métrica | Valor |
|---------|-------|
| RAM available (com stack full) | ~57 GiB |
| Modelo smoke | `gemma3:4b` (~3.3 GiB disk) |
| Bind | `127.0.0.1:11434` |
| Público `:11434` | **Connection refused** (UFW deny) |
| eval rate smoke | ~0.5 tok/s (CPU; aceitável para ops Q&A) |

**Nota:** `gemma3:12b` pode ser pullado depois se latência/qualidade do 4b for insuficiente.

---

## T-321b — Ollama production: localhost-only + systemd

- **Est**: 4h

### Objetivo

Ollama persistente, **nunca** bind público.

### Checklist

- [x] Instalar Ollama via `components/ssdnodes/install_ollama.sh`
- [x] systemd override `127.0.0.1:11434`, parallel=1
- [x] UFW deny 11434 (via ufw_manager)
- [x] Modelo `gemma3:4b` pullado + smoke test

### Arquivos

| Path | Ação |
|------|------|
| `components/ssdnodes/ollama/systemd/ollama.service` | Novo |
| `components/ssdnodes/install_ollama.sh` | Novo |
| `oci-k8s-cluster/scripts/ssdnodes/deploy_fleet_copilot.sh` | Orquestrador (stub ok) |

### Validação

```bash
ssh ssdnodes-monstro "ss -tlnp | grep 11434"
# Esperado: 127.0.0.1:11434
curl --max-time 3 http://104.225.218.78:11434/api/tags
# Esperado: falha (timeout/refused)
```

### DoD

- Ollama active, localhost only, modelo pullado

---

## T-321c — fleet-ops-gateway (Rust): endpoints read-only

- **Est**: 1d

### Objetivo

HTTP API com comandos **fixos** — zero concatenação de input do usuário/LLM nos shells.

### Endpoints v1

| Método | Path | Comando server-side (hardcoded) |
|--------|------|----------------------------------|
| GET | `/health` | `ok` |
| GET | `/ops/host/disk` | `df -h` |
| GET | `/ops/host/memory` | `free -h` |
| GET | `/ops/host/load` | `uptime` |
| GET | `/ops/host/services-failed` | `systemctl list-units --type=service --state=failed --no-pager` |
| GET | `/ops/host/ssh-recent` | `journalctl -u ssh --since 24h --no-pager \| tail -200` |
| GET | `/ops/k8s/nodes` | `kubectl get nodes -o json` |
| GET | `/ops/k8s/pods-not-running` | `kubectl get pods -A --field-selector=status.phase!=Running -o json` |
| GET | `/ops/k8s/ingress` | `kubectl get ingress -A -o json` |
| GET | `/ops/k8s/warnings` | `kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp \| tail -100` |

### Requisitos de implementação

- [x] Crate `apps/fleet-ops-gateway/` (Axum, 10 endpoints + `/internal/chat`)
- [x] Deploy systemd `fleet-ops-gateway.service` — porta **18443** (8443 ocupada pelo nginx-ingress)
- [x] Auth Bearer + 404 sem token
- [x] Kubeconfig Role `view` dedicado — `rbac.yaml` + `setup_fleet_gateway_kubeconfig.sh` + `FLEET_KUBECONFIG`
  ```json
  {
    "endpoint": "/ops/k8s/nodes",
    "collected_at": "2026-05-30T20:00:00Z",
    "exit_code": 0,
    "stdout": "...",
    "stderr": ""
  }
  ```
- [x] Usuário OS dedicado `fleet-copilot` (sem sudo; grupo `systemd-journal` para `journalctl`)
- [ ] Bind: `127.0.0.1:8080` **ou** Tailscale IP `:8443` (TLS terminado por reverse proxy local)

### Fase 1.1 (backlog neste arquivo, não v1)

- Rotas parametrizadas `/ops/k8s/logs/{namespace}/{pod}` com regex `[a-z0-9-]+` apenas

### Arquivos

| Path | Ação |
|------|------|
| `apps/fleet-ops-gateway/` | Novo workspace Rust |
| `components/ssdnodes/fleet-ops-gateway/k8s/` ou systemd | Deploy |
| `components/ssdnodes/fleet-ops-gateway/rbac.yaml` | ClusterRole view |

### Validação

```bash
curl -s -H "Authorization: Bearer $GATEWAY_TOKEN" \
  https://<ts-ip>:8443/ops/host/disk | jq .exit_code
# Esperado: 0
# Tentativa kubectl delete via gateway → endpoint inexistente
```

### DoD

- 10 endpoints respondendo JSON
- [x] kubeconfig view-only aplicado e testado (`setup_fleet_gateway_kubeconfig.sh --verify`)

---

## T-321d — Auth mTLS ou Bearer no gateway

- **Est**: 4h

### Objetivo

Gateway inacessível sem credencial; resposta **404** (não 401) para paths protegidos sem token — padrão qdbback.

### Checklist

- [ ] Secret gerado offline: `openssl rand -hex 32` → `/etc/fleet-copilot/gateway.env` (chmod 600)
- [ ] Middleware Axum:
  - [ ] Header `Authorization: Bearer <token>` OU client cert mTLS
  - [ ] Token inválido → `404 Not Found` (ocultar existência)
  - [ ] `/health` pode retornar 200 só de localhost (sem auth) para systemd
- [ ] Reverse proxy Caddy/nginx local:
  - [ ] TLS cert self-signed ou Let's Encrypt **só** se exposto via Tailscale DNS interno
  - [ ] `client_auth` mTLS opcional para rs-observability-api
- [ ] Documentar rotação de token no runbook

### DoD

- Request sem token → 404
- Request com token → 200 nos endpoints ops

---

## T-321e — Manifests + TUI status

- **Est**: 4h

### Objetivo

Operabilidade igual outros componentes SSDNodes.

### Checklist

- [ ] Manifests versionados em `components/ssdnodes/fleet-copilot/`
- [ ] Opção TUI `k8s_ops_menu.sh`:
  - [ ] Status Ollama + gateway
  - [ ] Restart seguro
  - [ ] Últimas linhas de log
- [ ] Integrar em `deploy_ssdnodes_components.sh` subcomando `fleet-copilot`
- [ ] README seção Fleet Copilot em `components/ssdnodes/README.md`

### Validação

```bash
bash oci-k8s-cluster/scripts/ssdnodes/deploy_ssdnodes_components.sh fleet-copilot
# TUI opção status → green
```

### DoD

- Deploy idempotente documentado
- TUI mostra health

---

## Threat model (escopo T-321)

| Ameaça | Mitigação neste epic |
|--------|----------------------|
| Ollama público | 127.0.0.1 + UFW deny 11434 |
| RCE via prompt | Gateway não aceita comandos do LLM — só rotas fixas |
| kubectl write | RBAC view-only; endpoints não expõem apply/delete |
| DoS inferência | NUM_PARALLEL=1; timeout 15s/comando |
| Token leak | Bearer rotacionável; Tailscale ACL |

---

## Critérios de aceite (epic T-321)

- [ ] Ollama localhost + modelo escolhido no spike
- [ ] fleet-ops-gateway com 10 endpoints + auth
- [ ] Deploy via script/TUI
- [ ] Nenhuma porta 11434 acessível externamente

## Evidência (preencher na execução)

| Métrica | Valor |
|---------|-------|
| Modelo escolhido | _TBD_ |
| RAM livre pós-carga | _TBD_ |
| Latência p50 prompt | _TBD_ |
| Versão Ollama | _TBD_ |
