# Runbook — incidentes email automation (T-362 draft)

## OAuth comprometido / token vazado

1. Revogar app em https://myaccount.google.com/permissions
2. `kubectl delete secret gmail-oauth -n email-intelligence`
3. Rotacionar `PGCRYPTO_KEY` (dual-key — ver ENCRYPTION-spec.md)
4. Re-auth via n8n OAuth2 credential flow
5. Audit: `SELECT * FROM email_intel.audit_log ORDER BY created_at DESC LIMIT 50`

## Suspeita de exfiltração Postgres

1. `kubectl scale deploy/n8n -n n8n --replicas=0`
2. Snapshot PVC postgres + preservar logs
3. Rotacionar todas as senhas K8s
4. Review NetworkPolicy egress

## LLM classificação errada em massa

1. Pausar workflow no n8n UI
2. Query: `SELECT category, count(*) FROM email_intel.classifications GROUP BY 1`
3. Rollback labels Gmail (T-362e) via script revert
4. Ajustar prompt / threshold confidence

## Purge GDPR / user request

```sql
SET app.mailbox_id = '<uuid>';
-- admin role only
DELETE FROM email_intel.oauth_tokens WHERE mailbox_id = current_setting('app.mailbox_id')::uuid;
UPDATE email_intel.messages SET body_enc = NULL, snippet_enc = NULL WHERE mailbox_id = current_setting('app.mailbox_id')::uuid;
```

## Contatos

- Infra: Cursor / AI Radar
- n8n UI: https://n8n.ssdnodes.dnor.io (basic auth + owner)
