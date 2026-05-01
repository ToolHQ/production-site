//! `raw_items` table: collected upstream content prior to extraction.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

/// Lifecycle status of a raw item, mirroring the SQL CHECK in 0002.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RawItemStatus {
    /// Just inserted, ready to be picked up by the extractor.
    Pending,
    /// Extraction in progress (claimed by a worker).
    Extracting,
    /// Extraction succeeded.
    Extracted,
    /// Extraction failed and will not be retried automatically.
    Failed,
    /// Item explicitly skipped by the operator (e.g. paywalled).
    Skipped,
}

impl RawItemStatus {
    /// Persisted form.
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            RawItemStatus::Pending => "pending",
            RawItemStatus::Extracting => "extracting",
            RawItemStatus::Extracted => "extracted",
            RawItemStatus::Failed => "failed",
            RawItemStatus::Skipped => "skipped",
        }
    }

    /// Parse from the persisted string.
    ///
    /// # Errors
    ///
    /// Returns the offending value when not one of the documented variants.
    pub fn parse(value: &str) -> Result<Self, String> {
        match value {
            "pending" => Ok(RawItemStatus::Pending),
            "extracting" => Ok(RawItemStatus::Extracting),
            "extracted" => Ok(RawItemStatus::Extracted),
            "failed" => Ok(RawItemStatus::Failed),
            "skipped" => Ok(RawItemStatus::Skipped),
            other => Err(other.to_string()),
        }
    }
}

/// Strongly-typed row from `ai_radar.raw_items`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RawItem {
    /// Primary key.
    pub id: Uuid,
    /// FK to `sources.id`.
    pub source_id: Uuid,
    /// Upstream identifier (e.g. GitHub release id) or `None` for sources
    /// that do not provide one.
    pub external_id: Option<String>,
    /// URL of the upstream item.
    pub url: String,
    /// Optional title.
    pub title: Option<String>,
    /// Cleaned-up textual content (truncated to `MAX_RAW_CONTENT_BYTES`).
    pub raw_content: String,
    /// Idempotency key — typically `sha256(raw_content)` hex.
    pub content_hash: String,
    /// Pipeline status.
    pub status: RawItemStatus,
    /// Free-form metadata (e.g. RSS guid, `GitHub` `stargazers_count`).
    pub metadata_json: serde_json::Value,
    /// Upstream-provided publish date (best effort).
    pub published_at: Option<DateTime<Utc>>,
    /// When the collector ingested the item.
    pub collected_at: DateTime<Utc>,
}

/// Insert payload for [`RawItemRepository::insert_idempotent`].
#[derive(Debug, Clone)]
pub struct NewRawItem {
    /// FK to `sources.id`.
    pub source_id: Uuid,
    /// Upstream identifier.
    pub external_id: Option<String>,
    /// URL of the upstream item.
    pub url: String,
    /// Optional title.
    pub title: Option<String>,
    /// Cleaned-up textual content.
    pub raw_content: String,
    /// Optional override for the idempotency hash. When `None`,
    /// [`NewRawItem::compute_hash`] generates a SHA-256 of `raw_content`.
    pub content_hash: Option<String>,
    /// Free-form metadata.
    pub metadata_json: Option<serde_json::Value>,
    /// Upstream-provided publish date.
    pub published_at: Option<DateTime<Utc>>,
}

impl NewRawItem {
    /// Compute the SHA-256 hex digest of the raw content. Used as the
    /// default idempotency key when [`NewRawItem::content_hash`] is left
    /// `None`. Exposed publicly so callers can reuse the same algorithm
    /// for client-side deduplication.
    #[must_use]
    pub fn compute_hash(raw_content: &str) -> String {
        let mut hasher = Sha256::new();
        hasher.update(raw_content.as_bytes());
        format!("{:x}", hasher.finalize())
    }

    /// Resolve the effective hash that will hit Postgres.
    #[must_use]
    pub fn effective_hash(&self) -> String {
        self.content_hash
            .clone()
            .unwrap_or_else(|| Self::compute_hash(&self.raw_content))
    }

    /// Validate the payload before sending it to Postgres.
    ///
    /// # Errors
    ///
    /// Returns a `Validation`-shaped string when blank `url` or
    /// `raw_content`.
    pub fn validate(&self) -> Result<(), String> {
        if self.url.trim().is_empty() {
            return Err("url must not be empty".into());
        }
        if self.raw_content.is_empty() {
            return Err("raw_content must not be empty".into());
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_roundtrip() {
        for v in [
            RawItemStatus::Pending,
            RawItemStatus::Extracting,
            RawItemStatus::Extracted,
            RawItemStatus::Failed,
            RawItemStatus::Skipped,
        ] {
            assert_eq!(RawItemStatus::parse(v.as_str()).unwrap(), v);
        }
    }

    #[test]
    fn compute_hash_is_deterministic() {
        let h1 = NewRawItem::compute_hash("hello world");
        let h2 = NewRawItem::compute_hash("hello world");
        assert_eq!(h1, h2);
        assert_eq!(h1.len(), 64);
    }

    #[test]
    fn effective_hash_uses_override_when_present() {
        let item = NewRawItem {
            source_id: Uuid::nil(),
            external_id: None,
            url: "https://x".into(),
            title: None,
            raw_content: "x".into(),
            content_hash: Some("custom".into()),
            metadata_json: None,
            published_at: None,
        };
        assert_eq!(item.effective_hash(), "custom");
    }
}
