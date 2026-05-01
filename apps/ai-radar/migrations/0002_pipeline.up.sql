-- 0002_pipeline.up.sql
-- AI Radar — pipeline tables (raw_items, extracted_items, scores,
-- feedback, digests). FKs cascade on parent delete to keep the
-- pipeline graph consistent.

-- ── raw_items ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_radar.raw_items (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id     UUID        NOT NULL REFERENCES ai_radar.sources(id) ON DELETE CASCADE,
    external_id   TEXT,
    url           TEXT        NOT NULL,
    title         TEXT,
    raw_content   TEXT        NOT NULL,
    content_hash  TEXT        NOT NULL,
    status        TEXT        NOT NULL DEFAULT 'pending',
    metadata_json JSONB       NOT NULL DEFAULT '{}'::jsonb,
    published_at  TIMESTAMPTZ,
    collected_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT raw_items_status_check
        CHECK (status IN ('pending', 'extracting', 'extracted', 'failed', 'skipped')),
    CONSTRAINT raw_items_source_hash_uniq UNIQUE (source_id, content_hash)
);

CREATE INDEX IF NOT EXISTS raw_items_collected_at_desc_idx
    ON ai_radar.raw_items (collected_at DESC);

CREATE INDEX IF NOT EXISTS raw_items_status_idx
    ON ai_radar.raw_items (status) WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS raw_items_source_collected_idx
    ON ai_radar.raw_items (source_id, collected_at DESC);

-- ── extracted_items ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_radar.extracted_items (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    raw_item_id     UUID        NOT NULL REFERENCES ai_radar.raw_items(id) ON DELETE CASCADE,
    version         INTEGER     NOT NULL DEFAULT 1,
    extractor       TEXT        NOT NULL DEFAULT 'deterministic-v1',
    tool_name       TEXT,
    category        TEXT,
    summary         TEXT,
    problem_solved  TEXT,
    self_hosted     BOOLEAN,
    saas_only       BOOLEAN,
    license         TEXT,
    maturity        TEXT,
    risk_level      TEXT,
    stack_fit       TEXT,
    metadata_json   JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT extracted_items_version_check  CHECK (version >= 1),
    CONSTRAINT extracted_items_maturity_check CHECK (
        maturity IS NULL OR maturity IN ('experimental', 'beta', 'stable', 'mature', 'deprecated')
    ),
    CONSTRAINT extracted_items_risk_check CHECK (
        risk_level IS NULL OR risk_level IN ('low', 'medium', 'high')
    ),
    CONSTRAINT extracted_items_raw_version_uniq UNIQUE (raw_item_id, version)
);

CREATE INDEX IF NOT EXISTS extracted_items_category_idx
    ON ai_radar.extracted_items (category) WHERE category IS NOT NULL;

CREATE INDEX IF NOT EXISTS extracted_items_created_at_desc_idx
    ON ai_radar.extracted_items (created_at DESC);

-- ── scores ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_radar.scores (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    extracted_item_id  UUID        NOT NULL REFERENCES ai_radar.extracted_items(id) ON DELETE CASCADE,
    score              REAL        NOT NULL,
    decision           TEXT        NOT NULL,
    next_step          TEXT,
    reasons_json       JSONB       NOT NULL DEFAULT '[]'::jsonb,
    risks_json         JSONB       NOT NULL DEFAULT '[]'::jsonb,
    scoring_version    TEXT        NOT NULL DEFAULT 'deterministic-v1',
    metadata_json      JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT scores_score_range_check    CHECK (score >= 0.0 AND score <= 1.0),
    CONSTRAINT scores_decision_check       CHECK (decision IN ('adopt', 'test', 'monitor', 'ignore')),
    CONSTRAINT scores_extracted_version_uniq UNIQUE (extracted_item_id, scoring_version)
);

CREATE INDEX IF NOT EXISTS scores_score_decision_idx
    ON ai_radar.scores (score DESC, decision);

CREATE INDEX IF NOT EXISTS scores_created_at_desc_idx
    ON ai_radar.scores (created_at DESC);

-- ── feedback ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_radar.feedback (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    extracted_item_id  UUID        NOT NULL REFERENCES ai_radar.extracted_items(id) ON DELETE CASCADE,
    feedback_type      TEXT        NOT NULL,
    notes              TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT feedback_type_check CHECK (feedback_type IN (
        'useful',
        'irrelevant',
        'duplicate',
        'low_quality',
        'wrong_category',
        'adopted',
        'tested',
        'monitoring',
        'rejected'
    ))
);

CREATE INDEX IF NOT EXISTS feedback_extracted_item_idx
    ON ai_radar.feedback (extracted_item_id);

CREATE INDEX IF NOT EXISTS feedback_created_at_desc_idx
    ON ai_radar.feedback (created_at DESC);

-- ── digests ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_radar.digests (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    digest_type      TEXT        NOT NULL,
    period_start     TIMESTAMPTZ NOT NULL,
    period_end       TIMESTAMPTZ NOT NULL,
    markdown_content TEXT        NOT NULL,
    metadata_json    JSONB       NOT NULL DEFAULT '{}'::jsonb,
    generated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT digests_type_check CHECK (digest_type IN ('daily', 'weekly', 'monthly', 'custom')),
    CONSTRAINT digests_period_check CHECK (period_end >= period_start)
);

CREATE INDEX IF NOT EXISTS digests_type_period_idx
    ON ai_radar.digests (digest_type, period_start DESC);

CREATE INDEX IF NOT EXISTS digests_generated_at_desc_idx
    ON ai_radar.digests (generated_at DESC);
