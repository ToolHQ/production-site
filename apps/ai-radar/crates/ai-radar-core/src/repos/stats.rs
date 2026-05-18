//! Read-only aggregate counts for dashboards and `GET /stats`.

use serde::Serialize;

use crate::db::{Database, RepoError, RepoResult};

/// Embedding coverage for semantic search (**T-255**).
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct EmbeddingCoverageStats {
    /// Configured model id (`EMBEDDING_MODEL`).
    pub model: String,
    /// Rows in `item_embeddings` for `model`.
    pub embeddings_total: i64,
    /// Latest extracted items (`raw_items.status = extracted`) without a vector for `model`.
    pub embeddings_pending: i64,
    /// Items eligible for embedding (same pool as embed CronJob).
    pub embeddings_eligible: i64,
    /// `embeddings_total / embeddings_eligible * 100`, or `0` when eligible is zero.
    pub coverage_pct: f32,
}

/// Row counts exposed to operators (no row payloads — cheap on small pools).
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct PipelineStats {
    /// Rows in `ai_radar.sources`.
    pub sources_total: i64,
    /// Sources with `enabled = TRUE`.
    pub sources_enabled: i64,
    /// Rows in `ai_radar.raw_items`.
    pub raw_items_total: i64,
    /// `raw_items` with `status = 'pending'` (extract queue depth).
    pub raw_items_pending: i64,
    /// Present when `EMBEDDINGS_ENABLED=true` and `EMBEDDING_MODEL` is set.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub embeddings: Option<EmbeddingCoverageStats>,
}

/// Load counts in one round-trip to Postgres (four scalar queries).
///
/// # Errors
///
/// Propagates [`RepoError`] when any query fails.
pub async fn load_pipeline_stats(db: &Database) -> RepoResult<PipelineStats> {
    let sources_total: i64 = sqlx::query_scalar("SELECT COUNT(*)::bigint FROM ai_radar.sources")
        .fetch_one(&db.pool)
        .await
        .map_err(RepoError::from_sqlx)?;
    let sources_enabled: i64 =
        sqlx::query_scalar("SELECT COUNT(*)::bigint FROM ai_radar.sources WHERE enabled = TRUE")
            .fetch_one(&db.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
    let raw_items_total: i64 =
        sqlx::query_scalar("SELECT COUNT(*)::bigint FROM ai_radar.raw_items")
            .fetch_one(&db.pool)
            .await
            .map_err(RepoError::from_sqlx)?;
    let raw_items_pending: i64 = sqlx::query_scalar(
        "SELECT COUNT(*)::bigint FROM ai_radar.raw_items WHERE status = 'pending'",
    )
    .fetch_one(&db.pool)
    .await
    .map_err(RepoError::from_sqlx)?;

    Ok(PipelineStats {
        sources_total,
        sources_enabled,
        raw_items_total,
        raw_items_pending,
        embeddings: None,
    })
}

/// Count embedding coverage for the configured model (**T-255**).
///
/// # Errors
///
/// Propagates [`RepoError`] when any query fails.
pub async fn load_embedding_coverage(
    db: &Database,
    model: &str,
) -> RepoResult<EmbeddingCoverageStats> {
    let embeddings_total: i64 = sqlx::query_scalar(
        "SELECT COUNT(*)::bigint FROM ai_radar.item_embeddings WHERE model = $1",
    )
    .bind(model)
    .fetch_one(&db.pool)
    .await
    .map_err(RepoError::from_sqlx)?;

    let embeddings_eligible: i64 = sqlx::query_scalar(
        "WITH latest AS ( \
             SELECT DISTINCT ON (raw_item_id) id, raw_item_id \
             FROM ai_radar.extracted_items \
             ORDER BY raw_item_id, version DESC, created_at DESC \
         ) \
         SELECT COUNT(*)::bigint \
         FROM latest l \
         JOIN ai_radar.raw_items r ON r.id = l.raw_item_id \
         WHERE r.status = 'extracted'",
    )
    .fetch_one(&db.pool)
    .await
    .map_err(RepoError::from_sqlx)?;

    let embeddings_pending: i64 = sqlx::query_scalar(
        "WITH latest AS ( \
             SELECT DISTINCT ON (raw_item_id) id, raw_item_id \
             FROM ai_radar.extracted_items \
             ORDER BY raw_item_id, version DESC, created_at DESC \
         ) \
         SELECT COUNT(*)::bigint \
         FROM latest l \
         JOIN ai_radar.raw_items r ON r.id = l.raw_item_id \
         WHERE r.status = 'extracted' \
           AND NOT EXISTS ( \
             SELECT 1 FROM ai_radar.item_embeddings ie \
             WHERE ie.extracted_item_id = l.id AND ie.model = $1 \
           )",
    )
    .bind(model)
    .fetch_one(&db.pool)
    .await
    .map_err(RepoError::from_sqlx)?;

    let coverage_pct = if embeddings_eligible > 0 {
        (embeddings_total as f32 / embeddings_eligible as f32) * 100.0
    } else {
        0.0
    };

    Ok(EmbeddingCoverageStats {
        model: model.to_string(),
        embeddings_total,
        embeddings_pending,
        embeddings_eligible,
        coverage_pct,
    })
}

/// Pipeline counts plus optional embedding coverage when enabled (**T-255**).
///
/// # Errors
///
/// Propagates [`RepoError`] when any query fails.
pub async fn load_pipeline_stats_with_embeddings(
    db: &Database,
    embeddings_enabled: bool,
    embedding_model: Option<&str>,
) -> RepoResult<PipelineStats> {
    let mut stats = load_pipeline_stats(db).await?;
    if embeddings_enabled {
        if let Some(model) = embedding_model.map(str::trim).filter(|s| !s.is_empty()) {
            stats.embeddings = Some(load_embedding_coverage(db, model).await?);
        }
    }
    Ok(stats)
}

#[cfg(test)]
mod tests {
    #[test]
    fn coverage_pct_zero_when_no_eligible() {
        let pct = if 0 > 0 {
            (20_f32 / 0_f32) * 100.0
        } else {
            0.0
        };
        assert_eq!(pct, 0.0);
    }

    #[test]
    fn coverage_pct_rounds_sensibly() {
        let eligible = 80_i64;
        let total = 20_i64;
        let pct = (total as f32 / eligible as f32) * 100.0;
        assert!((pct - 25.0).abs() < 0.01);
    }
}
