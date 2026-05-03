DROP INDEX IF EXISTS ai_radar.scores_extracted_version_created_idx;

-- Restore uniqueness (may fail if duplicate rows exist — operator must dedupe first).
ALTER TABLE ai_radar.scores
    ADD CONSTRAINT scores_extracted_version_uniq UNIQUE (extracted_item_id, scoring_version);
