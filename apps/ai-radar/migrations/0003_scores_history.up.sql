-- T-166: allow multiple score rows per (extracted_item, scoring_version) for rescoring history.
ALTER TABLE ai_radar.scores DROP CONSTRAINT IF EXISTS scores_extracted_version_uniq;

CREATE INDEX IF NOT EXISTS scores_extracted_version_created_idx
    ON ai_radar.scores (extracted_item_id, scoring_version, created_at DESC);
