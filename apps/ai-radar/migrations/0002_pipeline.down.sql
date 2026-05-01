-- 0002_pipeline.down.sql
-- Rolls back the pipeline tables in dependency-safe order.

DROP TABLE IF EXISTS ai_radar.digests;
DROP TABLE IF EXISTS ai_radar.feedback;
DROP TABLE IF EXISTS ai_radar.scores;
DROP TABLE IF EXISTS ai_radar.extracted_items;
DROP TABLE IF EXISTS ai_radar.raw_items;
