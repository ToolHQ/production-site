//! `scores` repository.

use async_trait::async_trait;
use sqlx::Row;
use uuid::Uuid;

use crate::db::{Database, RepoError, RepoResult};
use crate::domain::{AdoptionSummary, Decision, NewScore, Score, ScoredItemSummary};

/// Operations on `scores`.
#[async_trait]
pub trait ScoreRepository: Send + Sync {
    /// Insert a score row. The `(extracted_item_id, scoring_version)`
    /// pair is unique; a duplicate raises [`RepoError::Conflict`].
    async fn insert(&self, payload: &NewScore) -> RepoResult<Score>;

    /// Most recent score for an extracted item across all scoring
    /// versions, ordered by `created_at DESC`.
    async fn get_latest(&self, extracted_item_id: Uuid) -> RepoResult<Score>;

    /// Top-N scores ordered by `score DESC, created_at DESC`. Useful
    /// for the digest and the dashboard.
    async fn list_top(&self, limit: i64) -> RepoResult<Vec<Score>>;

    /// Explorer list: each extracted item with its **latest** score (T-177).
    async fn list_scored_items(
        &self,
        limit: i64,
        offset: i64,
        decision: Option<&str>,
        category: Option<&str>,
        stars_tier: Option<&str>,
        quality_warn: Option<bool>,
        sort: ScoredItemSort,
    ) -> RepoResult<Vec<ScoredItemSummary>>;

    /// Count rows matching [`list_scored_items`] filters (for pagination).
    async fn count_scored_items(
        &self,
        decision: Option<&str>,
        category: Option<&str>,
        stars_tier: Option<&str>,
        quality_warn: Option<bool>,
    ) -> RepoResult<i64>;

    /// Full score history for one extracted item, newest first.
    async fn list_for_extracted_item(&self, extracted_item_id: Uuid) -> RepoResult<Vec<Score>>;
}

/// Sort order for [`ScoreRepository::list_scored_items`].
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum ScoredItemSort {
    #[default]
    ScoreDesc,
    ScoreAsc,
    ScoredAtDesc,
    /// Stars tier (viral → niche), then score.
    AdoptionDesc,
}

impl ScoredItemSort {
    /// Parse query param (`score_desc`, `score_asc`, `scored_at_desc`).
    ///
    /// # Errors
    ///
    /// Returns the offending token when unknown.
    pub fn parse(value: &str) -> Result<Self, String> {
        match value {
            "score_desc" | "" => Ok(Self::ScoreDesc),
            "score_asc" => Ok(Self::ScoreAsc),
            "scored_at_desc" => Ok(Self::ScoredAtDesc),
            "adoption_desc" => Ok(Self::AdoptionDesc),
            other => Err(format!("unknown sort '{other}'")),
        }
    }
}

const SELECT_COLS: &str = "id, extracted_item_id, score, decision, next_step, reasons_json, \
     risks_json, scoring_version, metadata_json, created_at";

fn row_to_score(row: &sqlx::postgres::PgRow) -> RepoResult<Score> {
    let raw_decision: String = row.try_get("decision").map_err(RepoError::from_sqlx)?;
    let decision = Decision::parse(&raw_decision)
        .map_err(|v| RepoError::Validation(format!("unknown scores.decision '{v}'")))?;

    Ok(Score {
        id: row.try_get("id").map_err(RepoError::from_sqlx)?,
        extracted_item_id: row
            .try_get("extracted_item_id")
            .map_err(RepoError::from_sqlx)?,
        score: row.try_get("score").map_err(RepoError::from_sqlx)?,
        decision,
        next_step: row.try_get("next_step").map_err(RepoError::from_sqlx)?,
        reasons_json: row.try_get("reasons_json").map_err(RepoError::from_sqlx)?,
        risks_json: row.try_get("risks_json").map_err(RepoError::from_sqlx)?,
        scoring_version: row
            .try_get("scoring_version")
            .map_err(RepoError::from_sqlx)?,
        metadata_json: row.try_get("metadata_json").map_err(RepoError::from_sqlx)?,
        created_at: row.try_get("created_at").map_err(RepoError::from_sqlx)?,
    })
}

/// Postgres implementation.
#[derive(Debug, Clone)]
pub struct PgScoreRepository {
    pool: sqlx::PgPool,
}

impl PgScoreRepository {
    /// Build a repository from a [`Database`].
    #[must_use]
    pub fn new(database: &Database) -> Self {
        Self {
            pool: database.pool.clone(),
        }
    }
}

#[async_trait]
impl ScoreRepository for PgScoreRepository {
    async fn insert(&self, payload: &NewScore) -> RepoResult<Score> {
        payload.validate().map_err(RepoError::Validation)?;

        let sql = format!(
            "INSERT INTO ai_radar.scores \
                 (extracted_item_id, score, decision, next_step, reasons_json, risks_json, \
                  scoring_version, metadata_json) \
             VALUES ($1, $2, $3, $4, COALESCE($5, '[]'::jsonb), COALESCE($6, '[]'::jsonb), \
                     $7, COALESCE($8, '{{}}'::jsonb)) \
             RETURNING {SELECT_COLS}"
        );
        let row = sqlx::query(&sql)
            .bind(payload.extracted_item_id)
            .bind(payload.score)
            .bind(payload.decision.as_str())
            .bind(&payload.next_step)
            .bind(payload.reasons_json.clone())
            .bind(payload.risks_json.clone())
            .bind(&payload.scoring_version)
            .bind(payload.metadata_json.clone())
            .fetch_one(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;

        row_to_score(&row)
    }

    async fn get_latest(&self, extracted_item_id: Uuid) -> RepoResult<Score> {
        let sql = format!(
            "SELECT {SELECT_COLS} FROM ai_radar.scores \
             WHERE extracted_item_id = $1 ORDER BY created_at DESC LIMIT 1"
        );
        let row = sqlx::query(&sql)
            .bind(extracted_item_id)
            .fetch_optional(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?
            .ok_or(RepoError::NotFound)?;
        row_to_score(&row)
    }

    async fn list_top(&self, limit: i64) -> RepoResult<Vec<Score>> {
        let sql = format!(
            "SELECT {SELECT_COLS} FROM ai_radar.scores \
             ORDER BY score DESC, created_at DESC LIMIT $1"
        );
        let rows = sqlx::query(&sql)
            .bind(limit)
            .fetch_all(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
        rows.iter().map(row_to_score).collect()
    }

    async fn list_for_extracted_item(&self, extracted_item_id: Uuid) -> RepoResult<Vec<Score>> {
        let sql = format!(
            "SELECT {SELECT_COLS} FROM ai_radar.scores \
             WHERE extracted_item_id = $1 ORDER BY created_at DESC"
        );
        let rows = sqlx::query(&sql)
            .bind(extracted_item_id)
            .fetch_all(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
        rows.iter().map(row_to_score).collect()
    }

    async fn count_scored_items(
        &self,
        decision: Option<&str>,
        category: Option<&str>,
        stars_tier: Option<&str>,
        quality_warn: Option<bool>,
    ) -> RepoResult<i64> {
        let count: i64 = sqlx::query_scalar(
            "WITH latest_score AS ( \
                 SELECT DISTINCT ON (extracted_item_id) extracted_item_id, decision \
                 FROM ai_radar.scores \
                 ORDER BY extracted_item_id, created_at DESC \
             ) \
             SELECT COUNT(*)::bigint \
             FROM latest_score ls \
             JOIN ai_radar.extracted_items ei ON ei.id = ls.extracted_item_id \
             WHERE ($1::text IS NULL OR ls.decision = $1) \
               AND ($2::text IS NULL OR ei.category = $2) \
               AND ($3::text IS NULL OR ei.metadata_json->'adoption'->>'stars_tier' = $3) \
               AND ($4::bool IS NULL OR COALESCE((ei.metadata_json->>'quality_warn')::boolean, false) = $4)",
        )
        .bind(decision)
        .bind(category)
        .bind(stars_tier)
        .bind(quality_warn)
        .fetch_one(&self.pool)
        .await
        .map_err(RepoError::from_sqlx)?;
        Ok(count)
    }

    async fn list_scored_items(
        &self,
        limit: i64,
        offset: i64,
        decision: Option<&str>,
        category: Option<&str>,
        stars_tier: Option<&str>,
        quality_warn: Option<bool>,
        sort: ScoredItemSort,
    ) -> RepoResult<Vec<ScoredItemSummary>> {
        let order = match sort {
            ScoredItemSort::ScoreDesc => "ls.score DESC, ls.created_at DESC",
            ScoredItemSort::ScoreAsc => "ls.score ASC, ls.created_at DESC",
            ScoredItemSort::ScoredAtDesc => "ls.created_at DESC",
            ScoredItemSort::AdoptionDesc => {
                "CASE ei.metadata_json->'adoption'->>'stars_tier' \
                 WHEN 'viral' THEN 4 WHEN 'popular' THEN 3 WHEN 'growing' THEN 2 WHEN 'niche' THEN 1 ELSE 0 END DESC, \
                 ls.score DESC, ls.created_at DESC"
            }
        };
        let sql = format!(
            "WITH latest_score AS ( \
                 SELECT DISTINCT ON (extracted_item_id) \
                     extracted_item_id, score, decision, created_at \
                 FROM ai_radar.scores \
                 ORDER BY extracted_item_id, created_at DESC \
             ) \
             SELECT \
                 ei.id AS extracted_item_id, \
                 ei.tool_name, \
                 ei.category, \
                 ei.summary, \
                 ls.score, \
                 ls.decision, \
                 ls.created_at AS scored_at, \
                 ei.created_at AS extracted_at, \
                 ei.metadata_json->'adoption'->>'stars_tier' AS stars_tier, \
                 ei.metadata_json->'adoption'->>'activity_tier' AS activity_tier, \
                 (ei.metadata_json->'adoption'->>'stars')::bigint AS stars, \
                 COALESCE((ei.metadata_json->>'quality_warn')::boolean, false) AS quality_warn \
             FROM latest_score ls \
             JOIN ai_radar.extracted_items ei ON ei.id = ls.extracted_item_id \
             WHERE ($1::text IS NULL OR ls.decision = $1) \
               AND ($2::text IS NULL OR ei.category = $2) \
               AND ($3::text IS NULL OR ei.metadata_json->'adoption'->>'stars_tier' = $3) \
               AND ($4::bool IS NULL OR COALESCE((ei.metadata_json->>'quality_warn')::boolean, false) = $4) \
             ORDER BY {order} \
             LIMIT $5 OFFSET $6"
        );
        let rows = sqlx::query(&sql)
            .bind(decision)
            .bind(category)
            .bind(stars_tier)
            .bind(quality_warn)
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.pool)
            .await
            .map_err(RepoError::from_sqlx)?;

        rows.iter()
            .map(|row| {
                let raw_decision: String =
                    row.try_get("decision").map_err(RepoError::from_sqlx)?;
                let decision = Decision::parse(&raw_decision).map_err(|v| {
                    RepoError::Validation(format!("unknown scores.decision '{v}'"))
                })?;
                let stars_tier: Option<String> = row.try_get("stars_tier").ok();
                let activity_tier: Option<String> = row.try_get("activity_tier").ok();
                let stars: Option<i64> = row.try_get("stars").ok();
                let adoption = if stars_tier.is_some() || activity_tier.is_some() || stars.is_some()
                {
                    Some(AdoptionSummary {
                        stars_tier,
                        activity_tier,
                        stars,
                    })
                } else {
                    None
                };
                let quality_warn: bool = row.try_get("quality_warn").unwrap_or(false);
                Ok(ScoredItemSummary {
                    extracted_item_id: row
                        .try_get("extracted_item_id")
                        .map_err(RepoError::from_sqlx)?,
                    tool_name: row.try_get("tool_name").map_err(RepoError::from_sqlx)?,
                    category: row.try_get("category").map_err(RepoError::from_sqlx)?,
                    summary: row.try_get("summary").map_err(RepoError::from_sqlx)?,
                    score: row.try_get("score").map_err(RepoError::from_sqlx)?,
                    decision,
                    scored_at: row.try_get("scored_at").map_err(RepoError::from_sqlx)?,
                    extracted_at: row
                        .try_get("extracted_at")
                        .map_err(RepoError::from_sqlx)?,
                    adoption,
                    quality_warn: quality_warn.then_some(true),
                })
            })
            .collect()
    }
}

#[cfg(test)]
mod integration {
    use super::*;
    use crate::db::Database;
    use crate::domain::{Decision, NewExtractedItem, NewRawItem, NewScore, NewSource, SourceType};
    use crate::repos::extracted_item::{ExtractedItemRepository, PgExtractedItemRepository};
    use crate::repos::raw_item::{PgRawItemRepository, RawItemRepository};
    use crate::repos::source::{PgSourceRepository, SourceRepository};

    async fn db_handle() -> Database {
        let url =
            std::env::var("DATABASE_URL").expect("DATABASE_URL must be set for ignored tests");
        Database::connect(&url).await.expect("connect")
    }

    async fn cleanup(pool: &sqlx::PgPool) {
        sqlx::query("TRUNCATE ai_radar.sources CASCADE")
            .execute(pool)
            .await
            .expect("cleanup");
    }

    async fn seed_extracted(db: &Database, slug: &str) -> Uuid {
        let src_id = PgSourceRepository::new(db)
            .create(&NewSource {
                name: "score-src".into(),
                source_type: SourceType::Rss,
                url: format!("https://score.example.com/{slug}.xml"),
                enabled: None,
                poll_interval_minutes: None,
                metadata_json: None,
            })
            .await
            .unwrap()
            .id;
        let raw_id = PgRawItemRepository::new(db)
            .insert_idempotent(&NewRawItem {
                source_id: src_id,
                external_id: None,
                url: format!("https://score.example.com/{slug}"),
                title: None,
                raw_content: format!("c-{slug}"),
                content_hash: None,
                metadata_json: None,
                published_at: None,
            })
            .await
            .unwrap()
            .unwrap()
            .id;
        PgExtractedItemRepository::new(db)
            .insert(&NewExtractedItem {
                raw_item_id: raw_id,
                extractor: "deterministic-v1".into(),
                ..Default::default()
            })
            .await
            .unwrap()
            .id
    }

    #[tokio::test]
    #[ignore = "requires Postgres; run with --ignored"]
    async fn insert_then_list_top() {
        let db = db_handle().await;
        cleanup(&db.pool).await;
        let extracted_id_a = seed_extracted(&db, "a").await;
        let extracted_id_b = seed_extracted(&db, "b").await;
        let repo = PgScoreRepository::new(&db);

        repo.insert(&NewScore {
            extracted_item_id: extracted_id_a,
            score: 0.42,
            decision: Decision::Test,
            next_step: None,
            reasons_json: None,
            risks_json: None,
            scoring_version: "deterministic-v1".into(),
            metadata_json: None,
        })
        .await
        .unwrap();

        repo.insert(&NewScore {
            extracted_item_id: extracted_id_b,
            score: 0.81,
            decision: Decision::Adopt,
            next_step: Some("deploy in staging".into()),
            reasons_json: None,
            risks_json: None,
            scoring_version: "deterministic-v1".into(),
            metadata_json: None,
        })
        .await
        .unwrap();

        let top = repo.list_top(10).await.unwrap();
        assert_eq!(top.len(), 2);
        assert!(top[0].score > top[1].score, "must be ordered DESC by score");
        assert_eq!(top[0].decision, Decision::Adopt);

        let latest = repo.get_latest(extracted_id_b).await.unwrap();
        assert_eq!(latest.decision, Decision::Adopt);

        cleanup(&db.pool).await;
    }
}
