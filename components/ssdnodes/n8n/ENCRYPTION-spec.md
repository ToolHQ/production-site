# Criptografia — Postgres email intelligence (T-362)

## Chaves

| Secret K8s | Uso |
|------------|-----|
| `PGCRYPTO_KEY` | `pgp_sym_encrypt/decrypt` (32+ bytes, base64) |
| `postgres-password` | role admin migrations |
| `n8n-db-password` | role `n8n_app` |

Rotação: dual-key window 7d — coluna `key_version` em `messages`.

## Campos cifrados (`BYTEA`)

| Tabela | Coluna | Plaintext |
|--------|--------|-----------|
| `messages` | `body_enc` | corpo truncado armazenado (max 32k) |
| `messages` | `snippet_enc` | preview 200 chars |
| `oauth_tokens` | `refresh_token_enc` | Gmail refresh |

Campos **não** cifrados (index/search): `subject_hash`, `from_domain`, `received_at`, `gmail_message_id`, `category`.

## Funções SQL

```sql
-- app role only
CREATE OR REPLACE FUNCTION encrypt_pii(plain text)
RETURNS bytea LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT pgp_sym_encrypt(plain, current_setting('app.pgcrypto_key'));
$$;

CREATE OR REPLACE FUNCTION decrypt_pii(cipher bytea)
RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT pgp_sym_decrypt(cipher, current_setting('app.pgcrypto_key'));
$$;
```

`app.pgcrypto_key` set via `SET LOCAL` no início de cada transação n8n (Postgres node).

## Backup

```bash
# Nunca commitar output
kubectl exec -n email-intelligence sts/postgresql -- \
  pg_dump -U postgres email_intel | gpg -c > email-intel-$(date +%F).sql.gpg
```

## Purge (retention)

- Raw body: 30 dias → `body_enc = NULL`, manter metadata
- Audit log: 1 ano → partition drop
- OAuth: revogar + DELETE on user request
