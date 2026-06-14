# ADR: Email classification automation (T-362)

## Status

Proposed — implementação faseada via subtasks T-362a…f

## Contexto

Classificar e organizar emails com n8n + Ollama local, persistindo metadados em Postgres com RLS e campos sensíveis cifrados. **T-361** entregou n8n em `https://n8n.ssdnodes.dnor.io` (SQLite MVP).

## Decisões

### 1. Provider de email: **Gmail API + OAuth 2.0**

| | Gmail API | IMAP app password |
|---|-----------|-------------------|
| Segurança | Scopes granulares, revogação central | Credencial long-lived |
| Labels | Nativo | Limitado |
| Google policy | OAuth oficial | App passwords restritos |

**Scopes mínimos v1:** `gmail.readonly`, `gmail.modify` (labels only — sem send/delete).

**Conta:** OAuth de usuário único (owner); multi-mailbox = fase 2 com RLS `mailbox_id`.

### 2. Postgres: **K8s dedicado** (namespace `email-intelligence`)

- Bitnami PostgreSQL chart (padrão Sonar DB no SSDNodes)
- **ClusterIP only** — sem Ingress
- PVC 20Gi `local-path` (MVP single user)
- n8n credentials workflow → DB role `n8n_app` (RLS)

SQLite do n8n (workflows) **permanece** separado do Postgres de email.

### 3. Ollama: **Service + Endpoints → host loopback via socat**

Ollama escuta `127.0.0.1:11434` (T-321). Pods n8n não usam hostNetwork.

```
127.0.0.1:11434 (ollama)
    ↑
socat @ 10.244.0.1:11434 (host, UFW: allow from pod CIDR only)
    ↑
Service ollama-host:11434 (Endpoints manual)
    ↑
n8n HTTP Request node
```

Implementação em **T-362c** — não expor 11434 na internet (UFW deny mantido).

### 4. Modelo LLM v1

- **gemma3:4b** ou **qwen2.5:3b** (já no SSDNodes via `install_ollama.sh`)
- Saída **JSON estrito** via prompt + `format: json` Ollama API
- Truncar body a **4k chars** antes do LLM; hash SHA256 do body completo armazenado

### 5. Taxonomia v1

| category | priority default | action |
|----------|------------------|--------|
| `finance` | high | label + star |
| `alerts` | high | label |
| `newsletters` | low | label + archive candidate |
| `personal` | medium | inbox |
| `work` | medium | label |
| `spam-review` | low | quarantine label |
| `unclassified` | low | manual review |

## Fases (subtasks)

| ID | Entrega | Est. |
|----|---------|------|
| T-362a | Postgres K8s + migrations + RLS | 1d |
| T-362b | Gmail OAuth app + n8n credential vault | 1d |
| T-362c | Ollama host bridge + n8n HTTP node test | 4h |
| T-362d | Workflow classify (synthetic → staging Gmail) | 1d |
| T-362e | Label apply + audit log | 1d |
| T-362f | Harness + retention CronJob | 4h |

## Consequências

- Secrets: Google OAuth client, DB password, `PGCRYPTO_KEY` — K8s Secret only
- n8n workflows exportados **sem** credenciais (JSON sanitizado)
- Logs n8n: desabilitar execution data retention > 7d para runs com PII

Ver também: [THREAT-MODEL-email-automation.md](THREAT-MODEL-email-automation.md), [schema/001_init.sql](schema/001_init.sql)
