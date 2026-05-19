-- 0008_model_catalog.up.sql — OpenRouter model/pricing diff (**T-270**).

CREATE TABLE IF NOT EXISTS ai_radar.model_catalog_runs (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    provider      TEXT        NOT NULL DEFAULT 'openrouter',
    model_count   INTEGER     NOT NULL,
    events_count  INTEGER     NOT NULL DEFAULT 0,
    collected_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ai_radar.model_catalog_state (
    provider          TEXT        NOT NULL,
    model_id          TEXT        NOT NULL,
    model_name        TEXT,
    prompt_price      TEXT,
    completion_price  TEXT,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (provider, model_id)
);

CREATE TABLE IF NOT EXISTS ai_radar.model_catalog_events (
    id                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id                   UUID        NOT NULL REFERENCES ai_radar.model_catalog_runs(id) ON DELETE CASCADE,
    model_id                 TEXT        NOT NULL,
    event_type               TEXT        NOT NULL,
    prompt_price             TEXT,
    completion_price         TEXT,
    previous_prompt_price    TEXT,
    previous_completion_price TEXT,
    metadata_json            JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT model_catalog_events_type_check CHECK (
        event_type IN ('model_added', 'model_removed', 'price_change')
    )
);

CREATE INDEX IF NOT EXISTS model_catalog_runs_collected_idx
    ON ai_radar.model_catalog_runs (collected_at DESC);

CREATE INDEX IF NOT EXISTS model_catalog_events_run_idx
    ON ai_radar.model_catalog_events (run_id);

CREATE INDEX IF NOT EXISTS model_catalog_events_created_idx
    ON ai_radar.model_catalog_events (created_at DESC);

CREATE INDEX IF NOT EXISTS model_catalog_events_type_idx
    ON ai_radar.model_catalog_events (event_type, created_at DESC);
