-- 0001_init.down.sql
-- Drops the `sources` table, its trigger, the touch function and the
-- `ai_radar` schema itself.
--
-- This is safe because the SQLx `_sqlx_migrations` ledger lives in the
-- `public` schema (the connection URL pins `search_path=public`).
-- Dropping `ai_radar` therefore does not affect the migration metadata
-- and `sqlx migrate run`/`migrate revert` cycles remain idempotent.
--
-- The `pgcrypto` extension is intentionally preserved because it can
-- be used by other tenants of the cluster-shared database.

DROP TRIGGER IF EXISTS sources_touch_updated_at ON ai_radar.sources;
DROP FUNCTION IF EXISTS ai_radar.tg_touch_updated_at();

DROP TABLE IF EXISTS ai_radar.sources;
DROP SCHEMA IF EXISTS ai_radar CASCADE;
