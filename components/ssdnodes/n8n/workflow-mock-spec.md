# n8n workflow mock — classificação email (T-362)

Workflow **staging only** — dados sintéticos até T-362b (OAuth).

## Trigger

- **Schedule:** cada 15 min (produção) / manual (dev)
- **Webhook test:** `POST /webhook/email-classify-test` (desabilitado em prod)

## Nodes (v1)

```
1. [Manual/Schedule Trigger]
2. [Function] Load synthetic payload OR Gmail fetch (T-362b)
3. [Postgres] INSERT messages (body_enc via encrypt_pii)
4. [HTTP Request] Ollama POST /api/generate
5. [Function] Parse JSON + validate schema
6. [IF] confidence >= 0.7
7a. [Postgres] INSERT classifications
7b. [Postgres] category = unclassified
8. [Postgres] INSERT audit_log
9. [NoOp] (T-362e: Gmail label apply)
```

## Payload sintético (node 2)

```json
{
  "gmail_message_id": "mock-{{ $now.toISO() }}",
  "from_domain": "billing@example.com",
  "subject": "Your invoice #12345",
  "body": "Amount due: $99.00. Payment link: https://example.com/pay",
  "received_at": "{{ $now.toISO() }}"
}
```

## Prompt Ollama (node 4)

```
System: You classify email. Reply ONLY valid JSON.
User: Classify this email.
From domain: {{ $json.from_domain }}
Subject: {{ $json.subject }}
Body excerpt: {{ $json.body.substring(0, 4000) }}

JSON schema:
{"category":"finance|alerts|newsletters|personal|work|spam-review|unclassified",
 "priority":"high|medium|low",
 "action":"label_name or null",
 "confidence":0.0-1.0}
```

**Ollama body:**

```json
{
  "model": "gemma3:4b",
  "stream": false,
  "format": "json",
  "prompt": "<above>"
}
```

URL: `http://ollama-host.email-intelligence.svc.cluster.local:11434/api/generate`

## Validação schema (node 5)

Rejeitar se `category` ∉ enum ou `confidence` NaN → audit `event_type=classify_error`.

## Segurança execução

- `EXECUTIONS_DATA_SAVE_ON_ERROR`: all
- `EXECUTIONS_DATA_SAVE_ON_SUCCESS`: none (evita PII em SQLite n8n)
- Credentials Gmail: n8n credential store (encrypted by N8N_ENCRYPTION_KEY)

## Export

Após build: Export workflow JSON → `components/ssdnodes/n8n/workflows/email-classify-v1.json` (**sanitizado**, sem creds).
