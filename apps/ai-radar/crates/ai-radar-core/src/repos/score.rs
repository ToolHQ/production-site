//! `scores` repository.

use async_trait::async_trait;
use sqlx::Row;
use uuid::Uuid;

use crate::db::{Database, RepoError, RepoResult};
use crate::domain::{Decision, NewScore, Score};

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
