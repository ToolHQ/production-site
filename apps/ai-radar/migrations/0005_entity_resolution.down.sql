-- 0005_entity_resolution.down.sql

DROP INDEX IF EXISTS ai_radar.raw_items_tool_key_collected_idx;
DROP INDEX IF EXISTS ai_radar.raw_items_tool_key_idx;

ALTER TABLE ai_radar.raw_items
    DROP COLUMN IF EXISTS canonical_url,
    DROP COLUMN IF EXISTS tool_key;
