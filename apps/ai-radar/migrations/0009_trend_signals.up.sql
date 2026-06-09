-- 0009_trend_signals.up.sql — Google Trends time series (T-363 / T-271)

CREATE TABLE IF NOT EXISTS ai_radar.trend_signals (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    term            TEXT        NOT NULL,
    geo             TEXT        NOT NULL DEFAULT 'US',
    time_window     TEXT        NOT NULL,
    interest_score  SMALLINT    NOT NULL CHECK (interest_score >= 0 AND interest_score <= 100),
    collected_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata_json   JSONB       NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS trend_signals_term_collected_idx
    ON ai_radar.trend_signals (term, geo, collected_at DESC);

CREATE INDEX IF NOT EXISTS trend_signals_collected_idx
    ON ai_radar.trend_signals (collected_at DESC);
