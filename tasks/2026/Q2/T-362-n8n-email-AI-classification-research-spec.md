# T-362: n8n + Ollama — classificação de email (research, ADR, subtasks)

- **Status**: Done
- **Priority**: 🚨 Critical
- **Owner**: Cursor / AI Radar
- **Epic**: SSDNodes Automation / n8n
- **Est**: 2d (research + specs apenas — **sem** produção de email nesta task)
- **Criado**: 2026-06-09
- **Depends on**: [T-361](T-361-SSDNodes-n8n-Docker-authenticated-TLS.md) (n8n live + TLS)
- **Deliverable**: docs, ADRs, threat model, subtasks — **não** automação em produção

## Context

Automatizar **classificação e organização de emails** via n8n no SSDNodes, usando **IA local** (Ollama/Gemma no `127.0.0.1:11434`) para zero custo variável e latência previsível.

**Segurança é extremamente essencial**: emails contêm PII, tokens, credenciais em thread, metadados sensíveis.

### Escopo desta task (planejamento)

Esta task **não** conecta IMAP/Gmail em produção. Entrega:

1. **Threat model** (STRIDE-lite) para email + LLM local + n8n
2. **ADR** de arquitetura de dados (Postgres dedicado no SSDNodes)
3. **Schema proposto** com RLS, criptografia em repouso, retention
4. **Workflow n8n** em modo mock/staging (dados sintéticos)
5. **Backlog de subtasks** (T-362a…) para implementação faseada

### Arquitetura alvo (proposta)

```
Gmail/IMAP (OAuth) → n8n (TLS) → Ollama localhost → classificação JSON
                              ↓
                    Postgres (RLS, pgcrypto)
                              ↓
                    labels/folders (Gmail API) — fase posterior
```

### Postgres — requisitos de segurança

| Requisito | Abordagem |
|-----------|-----------|
| Isolamento tenant | RLS por `user_id` / `mailbox_id` |
| Criptografia repouso | `pgcrypto` + `BYTEA` para body/snippets; KMS futuro opcional |
| Mínimo privilégio | role `n8n_app` sem `SUPERUSER`; migrations separadas |
| Audit | `email_events` append-only; sem delete sem policy |
| Retention | TTL por categoria (ex.: raw body 30d, labels 1y) |
| Network | Postgres **ClusterIP only**; sem NodePort público |
| Secrets | K8s Secret / arquivo root-only; nunca no Git |

### Integração IA local

- HTTP `http://127.0.0.1:11434/api/generate` ou OpenAI-compatible `/v1/chat/completions`
- Prompt estruturado → JSON schema (`category`, `priority`, `action`, `confidence`)
- **Nunca** enviar corpo completo para log; truncar + redact em traces
- Rate limit + timeout no n8n; fallback "unclassified"

### Provider email (research)

| Opção | Prós | Contras |
|-------|------|---------|
| Gmail API + OAuth | Granular scopes, labels nativos | Consent screen, quota |
| IMAP + app password | Simples | Menos seguro; deprecado Google |
| Microsoft Graph | Enterprise | Fora do escopo inicial |

Documentar decisão no ADR.

## Tasks

- [x] Threat model: superfícies (n8n UI, webhooks, Postgres, Ollama, OAuth tokens)
- [x] ADR: Postgres no K8s SSDNodes vs host Docker; sizing RAM; Gmail API
- [x] Schema draft: `mailboxes`, `messages`, `classifications`, `audit_log` + RLS policies SQL
- [x] Spec criptografia: campos `BYTEA`, rotação de key, backup cifrado
- [x] Workflow n8n mock spec (payload sintético — spike live em T-362d)
- [x] Class taxonomy v1: inbox, finance, alerts, newsletters, personal, spam-review
- [x] Subtasks: [T-362-EPIC-email-automation-subtasks.md](T-362-EPIC-email-automation-subtasks.md)
- [x] Runbook operacional draft: incident response, revogação OAuth, purge

## Out of scope (subtasks futuras)

- Conexão Gmail/IMAP produção
- Escrita em labels reais
- Notificações push
- Multi-usuário SaaS

## Acceptance

- `docs/` ou `components/ssdnodes/n8n/ADR-email-automation.md` mergeável
- Schema SQL revisável em `components/ssdnodes/n8n/schema/`
- Lista de subtasks com estimativas no KANBAN
- Revisão de segurança explícita: **nenhum segredo ou email real** no repo
