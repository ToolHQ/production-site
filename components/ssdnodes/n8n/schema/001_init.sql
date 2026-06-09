-- email-intelligence schema v1 (T-362)
-- Apply as superuser; app connects as n8n_app with RLS

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS email_intel;
SET search_path TO email_intel, public;

-- ─── Tenancy ───────────────────────────────────────────────────────────────
CREATE TABLE mailboxes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_email     TEXT NOT NULL UNIQUE,
    provider        TEXT NOT NULL DEFAULT 'gmail',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE oauth_tokens (
    mailbox_id      UUID PRIMARY KEY REFERENCES mailboxes(id) ON DELETE CASCADE,
    refresh_token_enc BYTEA NOT NULL,
    scopes          TEXT[] NOT NULL,
    expires_at      TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─── Messages ───────────────────────────────────────────────────────────────
CREATE TABLE messages (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mailbox_id        UUID NOT NULL REFERENCES mailboxes(id) ON DELETE CASCADE,
    gmail_message_id  TEXT NOT NULL,
    thread_id         TEXT,
    from_domain       TEXT,
    subject_hash      TEXT,          -- sha256 hex of subject (search without plaintext)
    body_enc          BYTEA,
    snippet_enc       BYTEA,
    body_sha256       TEXT,          -- full body hash for dedup
    received_at       TIMESTAMPTZ NOT NULL,
    ingested_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    key_version       SMALLINT NOT NULL DEFAULT 1,
    UNIQUE (mailbox_id, gmail_message_id)
);

CREATE INDEX messages_mailbox_received ON messages (mailbox_id, received_at DESC);
CREATE INDEX messages_from_domain ON messages (mailbox_id, from_domain);

-- ─── Classifications ───────────────────────────────────────────────────────
CREATE TABLE classifications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id      UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    category        TEXT NOT NULL CHECK (category IN (
        'finance','alerts','newsletters','personal','work','spam-review','unclassified'
    )),
    priority        TEXT NOT NULL CHECK (priority IN ('high','medium','low')),
    action          TEXT,
    confidence      REAL NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    model           TEXT NOT NULL,
    prompt_tokens   INT,
    classified_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (message_id)
);

CREATE INDEX classifications_category ON classifications (category, classified_at DESC);

-- ─── Audit (append-only) ───────────────────────────────────────────────────
CREATE TABLE audit_log (
    id              BIGSERIAL PRIMARY KEY,
    mailbox_id      UUID NOT NULL REFERENCES mailboxes(id),
    event_type      TEXT NOT NULL,
    message_id      UUID,
    payload         JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX audit_log_mailbox_time ON audit_log (mailbox_id, created_at DESC);

-- ─── RLS ───────────────────────────────────────────────────────────────────
ALTER TABLE mailboxes ENABLE ROW LEVEL SECURITY;
ALTER TABLE oauth_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE classifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- Session var: SET app.mailbox_id = '<uuid>';

CREATE POLICY mailboxes_isolation ON mailboxes
    USING (id = current_setting('app.mailbox_id', true)::uuid)
    WITH CHECK (id = current_setting('app.mailbox_id', true)::uuid);

CREATE POLICY oauth_isolation ON oauth_tokens
    USING (mailbox_id = current_setting('app.mailbox_id', true)::uuid)
    WITH CHECK (mailbox_id = current_setting('app.mailbox_id', true)::uuid);

CREATE POLICY messages_isolation ON messages
    USING (mailbox_id = current_setting('app.mailbox_id', true)::uuid)
    WITH CHECK (mailbox_id = current_setting('app.mailbox_id', true)::uuid);

CREATE POLICY classifications_isolation ON classifications
    USING (message_id IN (
        SELECT id FROM messages WHERE mailbox_id = current_setting('app.mailbox_id', true)::uuid
    ))
    WITH CHECK (message_id IN (
        SELECT id FROM messages WHERE mailbox_id = current_setting('app.mailbox_id', true)::uuid
    ));

CREATE POLICY audit_isolation ON audit_log
    USING (mailbox_id = current_setting('app.mailbox_id', true)::uuid)
    WITH CHECK (mailbox_id = current_setting('app.mailbox_id', true)::uuid);

-- ─── Roles ─────────────────────────────────────────────────────────────────
DO $$ BEGIN
    CREATE ROLE n8n_app LOGIN;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA email_intel TO n8n_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA email_intel TO n8n_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA email_intel TO n8n_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA email_intel GRANT SELECT, INSERT, UPDATE ON TABLES TO n8n_app;

-- n8n_app cannot DELETE messages (retention via admin CronJob only)
