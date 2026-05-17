-- 0005_entity_resolution.up.sql — cross-source tool_key on raw_items (**T-231**).

ALTER TABLE ai_radar.raw_items
    ADD COLUMN IF NOT EXISTS tool_key TEXT,
    ADD COLUMN IF NOT EXISTS canonical_url TEXT;

CREATE INDEX IF NOT EXISTS raw_items_tool_key_idx
    ON ai_radar.raw_items (tool_key)
    WHERE tool_key IS NOT NULL AND status <> 'skipped';

CREATE INDEX IF NOT EXISTS raw_items_tool_key_collected_idx
    ON ai_radar.raw_items (tool_key, collected_at DESC)
    WHERE tool_key IS NOT NULL;
