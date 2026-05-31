# T-322: Fleet Copilot — Proxy seguro no reports (rs-observability-api)

- **Status**: Done (MVP 2026-05-31 — auth, chat, SSE stream, rate limit; backlog: audit Postgres T-322e)
- **Priority**: 🔼 High
- **Owner**: Cursor / AI Radar
- **Epic**: Fleet Copilot / reports.dnor.io
- **Est**: 3d (322a–322f)
- **Depends on**: T-321 (gateway + Ollama no monstro)
- **Blocks**: T-323

## Context

Camada OCI que:

1. **Autentica** o operador (padrão qdbback monitor)
2. **Rate-limita** requests
3. **Coleta contexto no servidor** (live overview + fleet-ops-gateway) — **nunca** confia em contexto do browser
4. **Chama Ollama no monstro** via Tailscale para sintetizar resposta read-only
5. **Fail-closed**: desligado por default

**Não** expor OpenRouter, chaves LLM ou URL do monstro ao frontend.

Arquivos centrais hoje:

- `apps/rs-observability-api/src/app.rs` — rotas GET-only
- `apps/rs-observability-api/k8s/rs-observability-api.yaml` — ingress sem auth
- `apps/qdbback/services/monitorAuth.js` — referência auth

---

## Modelo de auth (copiar qdbback)

| Etapa | Comportamento |
|-------|-------------|
| Login | `GET /fleet-copilot?key=<FLEET_COPILOT_LOGIN_KEY>` → set cookie `fleet-copilot-session` (HttpOnly, Secure, Max-Age=28800) |
| Cookie | HMAC-SHA256 derivado de `FLEET_COPILOT_SESSION_SECRET` |
| Falha | `404 Not Found` (não revelar endpoint) |
| Chat API | `POST /api/fleet/chat` exige cookie válido |

Secrets K8s (manual, não versionados):

```bash
kubectl create secret generic fleet-copilot-creds \
  --from-literal=FLEET_COPILOT_LOGIN_KEY="$(openssl rand -hex 16)" \
  --from-literal=FLEET_COPILOT_SESSION_SECRET="$(openssl rand -hex 32)" \
  --from-literal=FLEET_COPILOT_GATEWAY_TOKEN="<mesmo token do T-321d>" \
  -n <namespace>
```

---

## T-322a — Auth middleware + rotas login

- **Est**: 4h

### Checklist

- [ ] Módulo `src/fleet_copilot/auth.rs`:
  - [ ] `login_handler` — valida query `key`, emite cookie
  - [ ] `require_session` middleware — valida cookie em `/api/fleet/chat*`
  - [ ] Cookie inválido → 404
- [ ] `FLEET_COPILOT_ENABLED=false` default → rotas chat retornam 404
- [ ] Testes unitários: cookie round-trip, key errada → 404

### Arquivos

| Path | Ação |
|------|------|
| `apps/rs-observability-api/src/fleet_copilot/auth.rs` | Novo |
| `apps/rs-observability-api/src/app.rs` | Registrar rotas |

### DoD

- Login flow funciona com secret de teste
- Feature flag desliga tudo

---

## T-322b — Handler POST /api/fleet/chat (non-stream MVP)

- **Est**: 1d

### Fluxo

```
1. Validar sessão + rate limit
2. Parse body JSON { "message": string, "preset": optional }
3. Rejeitar message > 4000 chars; body total < 64 KiB
4. Paralelo:
   a. Cache live overview (LiveMonitor + Prometheus — já existente)
   b. Fetch fleet-ops-gateway endpoints relevantes ao preset/intent
5. Montar prompt SERVER-SIDE (template fixo):
   - system: "Você é assistente read-only. Cite apenas dados JSON abaixo."
   - user data: JSON agregado dos endpoints
   - user question: message sanitizada
6. POST Ollama OpenAI-compatible http://<monstro-tailscale>:11434/v1/chat/completions
   OU delegar síntese ao gateway se expuser /v1/chat proxy interno
7. Retornar JSON { reply, sources[], model, latency_ms, request_id }
```

### Presets v1 (server-side enum — não freeform de URLs)

| Preset ID | Endpoints gateway chamados |
|-----------|---------------------------|
| `ssdnodes-health` | disk, memory, services-failed, nodes |
| `ssdnodes-k8s` | pods-not-running, ingress, warnings |
| `ssdnodes-ssh` | ssh-recent |
| `custom` | subset mínimo disk + nodes (default seguro) |

### Checklist

- [ ] DTO `FleetChatRequest` / `FleetChatResponse`
- [ ] **Proibir** campo `context` ou `system_prompt` no body cliente
- [ ] Intent: se `preset` ausente, mapear keywords simples → preset (whitelist)
- [ ] Timeout total 60s (`tokio::time::timeout`)
- [ ] Erros tipados `FleetChatError` → JSON sem stack trace

### DoD

- curl autenticado retorna resposta grounded em JSON real
- Pergunta "delete all pods" → resposta explicando read-only, sem execução

---

## T-322c — Rate limit + concorrência + body limits

- **Est**: 4h

### Limites v1

| Limite | Valor |
|--------|-------|
| Body max | 64 KiB |
| Message max | 4000 chars |
| Requests | 10/min por IP (in-memory; documentar limitação multi-replica) |
| Concurrent chats | 1 global (`Semaphore`) |
| Ollama RPM | 6/min (espaçamento ~10s) |

### Checklist

- [ ] `DefaultBodyLimit::max(64 * 1024)` + `RequestBodyLimitLayer`
- [ ] Middleware rate limit IP (`HashMap<IpAddr, Vec<Instant>>` ou `tower_governor`)
- [ ] `Semaphore(1)` para inferência concurrent
- [ ] Resposta `429 Too Many Requests` com `Retry-After`
- [ ] Copiar padrão pacing de `apps/ai-radar/crates/ai-radar-core/src/llm/pace.rs`

### DoD

- 11º request/min → 429
- 2º chat concurrent → 503 ou queue reject documentado

---

## T-322d — Ingress + K8s secrets + resource limits

- **Est**: 2h

### Checklist manifest `rs-observability-api.yaml`

- [ ] Annotations:
  ```yaml
  nginx.ingress.kubernetes.io/limit-rps: "5"
  nginx.ingress.kubernetes.io/limit-burst-multiplier: "3"
  nginx.ingress.kubernetes.io/proxy-body-size: "64k"
  ```
- [ ] EnvFrom secret `fleet-copilot-creds` (optional keys)
- [ ] Env:
  ```yaml
  FLEET_COPILOT_ENABLED: "false"  # opt-in deploy
  FLEET_COPILOT_GATEWAY_URL: "https://100.x.x.x:8443"
  FLEET_COPILOT_OLLAMA_URL: "http://100.x.x.x:11434/v1"  # via tailscale — prefer proxy no gateway
  ```
- [ ] Memory limit pod: **512Mi** (subir de 256Mi)
- [ ] **Não** montar `ssdnodes-kubeconfig` no path de chat se não necessário — least privilege review

### DoD

- Manifest aplicável com feature off by default
- Documentação `kubectl create secret` no task body

---

## T-322e — Audit log

- **Est**: 4h

### Objetivo

Trilha de auditoria sem guardar prompt completo por default (alinhado agent-meter).

### Checklist

- [ ] Schema Postgres `fleet_copilot.audit_events` **ou** SQLite sidecar com purge timer
  - Campos: `id`, `ts`, `client_ip`, `prompt_sha256`, `preset`, `endpoints_called[]`, `latency_ms`, `model`, `status`
  - **Não** armazenar `reply` completo por default (opcional flag debug)
- [ ] CronJob ou timer purge > 30 dias (padrão qdbback)
- [ ] Zero Variable Cost: Postgres compartilhado cluster OCI (schema dedicado)

### SQL sketch

```sql
CREATE SCHEMA IF NOT EXISTS fleet_copilot;
CREATE TABLE fleet_copilot.audit_events (
  id BIGSERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  client_ip INET,
  prompt_sha256 CHAR(64) NOT NULL,
  preset TEXT,
  endpoints TEXT[] NOT NULL,
  latency_ms INT,
  model TEXT,
  status TEXT NOT NULL
);
```

### DoD

- Cada chat gera 1 row audit
- Purge documentado

---

## T-322f — SSE streaming (fase 2 dentro deste epic, opcional pós-MVP)

- **Est**: 4h (pode mover para T-323 se atrasar)

### Checklist

- [ ] `POST /api/fleet/chat/stream` → `text/event-stream`
- [ ] Headers: `Cache-Control: no-cache`, `X-Accel-Buffering: no`
- [ ] Cancel upstream on client disconnect
- [ ] Sanitizar chunks SSE (max 8 KiB/event)

### DoD

- UI pode consumir stream (T-323c)

---

## T-322 — Testes

### Unit

- [ ] Auth 404 paths
- [ ] Body oversize 413
- [ ] Rate limit 429
- [ ] Prompt injection strings não passam para shell (mock gateway)

### Integration

- [ ] wiremock gateway + ollama responses
- [ ] Harness: `scripts/harness/validate_fleet_copilot.sh`

### Live (após deploy)

```bash
# Login (browser ou curl cookie jar)
curl -c /tmp/cj -s "https://reports.dnor.io/fleet-copilot?key=$KEY" -o /dev/null -w '%{http_code}'

curl -b /tmp/cj -X POST https://reports.dnor.io/api/fleet/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"Como está o disco no SSDNodes?","preset":"ssdnodes-health"}' | jq .
```

---

## Critérios de aceite (epic T-322)

- [ ] Feature **off** by default; **on** só com secret + env explícitos
- [ ] Auth estilo qdbback funcional
- [ ] Chat responde com dados reais do gateway
- [ ] Rate limits ativos
- [ ] Audit log gravando
- [ ] Nenhuma chave/token no frontend bundle
- [ ] Zero OpenRouter / API paga no path crítico

## Threat model (proxy layer)

| Ameaça | Mitigação |
|--------|-----------|
| Proxy LLM aberto | Auth cookie + FLEET_COPILOT_ENABLED |
| Prompt injection → RCE | Sem shell; só JSON gateway |
| DoS | Rate limit + semaphore |
| Exfil secrets via resposta | System prompt fixo; Ollama não vê kubeconfig |
| Token no JS | Cookie HttpOnly only |
