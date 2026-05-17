-- 0004_comparisons.up.sql — category comparison matrices (**T-168**).

CREATE TABLE IF NOT EXISTS ai_radar.comparisons (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    category     TEXT        NOT NULL,
    top_n        INTEGER     NOT NULL CHECK (top_n > 0 AND top_n <= 50),
    matrix_json  JSONB       NOT NULL,
    markdown     TEXT        NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS comparisons_category_generated_idx
    ON ai_radar.comparisons (category, generated_at DESC);
