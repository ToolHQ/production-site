-- 0001_init.up.sql
-- AI Radar — bootstrap schema and the `sources` table.
--
-- Idempotent: re-running this migration on a database that already has
-- the schema and table is a no-op. The destructive path lives in the
-- matching `0001_init.down.sql`.

CREATE SCHEMA IF NOT EXISTS ai_radar;

-- pgcrypto provides gen_random_uuid() (UUIDv4) without requiring the
-- uuid-ossp extension which is not always preinstalled.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS ai_radar.sources (
    id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name                  TEXT         NOT NULL,
    source_type           TEXT         NOT NULL,
    url                   TEXT         NOT NULL,
    enabled               BOOLEAN      NOT NULL DEFAULT TRUE,
    poll_interval_minutes INTEGER      NOT NULL DEFAULT 30,
    last_polled_at        TIMESTAMPTZ,
    last_error            TEXT,
    metadata_json         JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT sources_source_type_check
        CHECK (source_type IN ('rss', 'github_repo', 'github_releases', 'webpage', 'youtube')),
    CONSTRAINT sources_poll_interval_check
        CHECK (poll_interval_minutes >= 1 AND poll_interval_minutes <= 1440)
);

CREATE UNIQUE INDEX IF NOT EXISTS sources_url_source_type_uidx
    ON ai_radar.sources (source_type, url);

CREATE INDEX IF NOT EXISTS sources_enabled_idx
    ON ai_radar.sources (enabled) WHERE enabled = TRUE;

-- Touch trigger keeping `updated_at` in sync.
CREATE OR REPLACE FUNCTION ai_radar.tg_touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sources_touch_updated_at ON ai_radar.sources;
CREATE TRIGGER sources_touch_updated_at
    BEFORE UPDATE ON ai_radar.sources
    FOR EACH ROW EXECUTE FUNCTION ai_radar.tg_touch_updated_at();
