-- 0006_tool_metrics_snapshots.up.sql — star history for velocity (**T-234**).

CREATE TABLE IF NOT EXISTS ai_radar.tool_metrics_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tool_key TEXT NOT NULL,
    source_id UUID REFERENCES ai_radar.sources (id) ON DELETE SET NULL,
    stars BIGINT,
    forks BIGINT,
    open_issues BIGINT,
    collected_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS tool_metrics_snapshots_tool_key_time_idx
    ON ai_radar.tool_metrics_snapshots (tool_key, collected_at DESC);

CREATE INDEX IF NOT EXISTS tool_metrics_snapshots_collected_at_idx
    ON ai_radar.tool_metrics_snapshots (collected_at DESC);
