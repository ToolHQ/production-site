# Threat Model — Email + n8n + Ollama (T-362)

STRIDE-lite · escopo MVP single-user · **sem dados reais no Git**

## Ativos

| Ativo | Sensibilidade |
|-------|---------------|
| Corpo de email + anexos | 🔴 PII / segredos |
| OAuth refresh tokens (Gmail) | 🔴 |
| Postgres `messages.body_enc` | 🔴 |
| Classificações + audit log | 🟡 |
| Workflows n8n | 🟡 |
| Prompts enviados ao Ollama | 🟡 (truncados) |

## Superfícies de ataque

```
Internet → nginx ingress (443) → n8n UI/webhooks
n8n pod → Postgres (ClusterIP)
n8n pod → ollama-host:11434 (Endpoints)
n8n pod → Gmail API (HTTPS egress)
Operator → SSH / kubectl
```

## STRIDE

| Tipo | Cenário | Mitigação |
|------|---------|-----------|
| **S** Spoofing | Webhook n8n sem auth | Basic auth (T-361) + HMAC header opcional T-362d |
| **T** Tampering | ALTER messages | RLS + role sem DDL; audit append-only |
| **R** Repudiation | "n8n aplicou label errado" | `audit_log` imutável + execution id |
| **I** Info disclosure | Log n8n com body | Truncar/redact; EXECUTIONS_DATA_SAVE manual |
| **D** DoS | Loop Gmail poll | Rate limit 1/min; backoff |
| **E** Elevation | `n8n_app` → superuser | REVOKE ALL PUBLIC; migrations via admin role |

## Controles obrigatórios (implementação)

1. **Criptografia repouso:** `pgcrypto` + `BYTEA` — ver [ENCRYPTION-spec.md](ENCRYPTION-spec.md)
2. **RLS:** `mailbox_id` = session var `app.mailbox_id`
3. **OAuth:** refresh token só em K8s Secret; rotate anual
4. **Ollama:** nunca `0.0.0.0:11434` público; socat + UFW pod CIDR
5. **Backup:** `pg_dump` cifrado (gpg) off-cluster; **nunca** plain text email
6. **Incident response:** [RUNBOOK-email-incident.md](RUNBOOK-email-incident.md)

## Fora de escopo MVP

- Multi-tenant SaaS
- DLP scanning anexos
- HSM / Vault externo

## Aceite de risco documentado

- LLM local pode **alucinar** categoria → `confidence < 0.7` → `spam-review`
- Operator com SSH root no SSDNodes pode ler PVC — aceito (infra self-hosted)
