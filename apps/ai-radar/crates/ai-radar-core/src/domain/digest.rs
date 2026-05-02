//! `digests` table: generated Markdown reports.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Cadence of the digest, matching the SQL CHECK in 0002.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DigestType {
    /// Daily digest.
    Daily,
    /// Weekly digest.
    Weekly,
    /// Monthly digest.
    Monthly,
    /// Custom on-demand digest.
    Custom,
}

impl DigestType {
    /// Persisted form.
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            DigestType::Daily => "daily",
            DigestType::Weekly => "weekly",
            DigestType::Monthly => "monthly",
            DigestType::Custom => "custom",
        }
    }

    /// Parse the persisted form.
    ///
    /// # Errors
    ///
    /// Returns the offending value when not one of the documented variants.
    pub fn parse(value: &str) -> Result<Self, String> {
        match value {
            "daily" => Ok(DigestType::Daily),
            "weekly" => Ok(DigestType::Weekly),
            "monthly" => Ok(DigestType::Monthly),
            "custom" => Ok(DigestType::Custom),
            other => Err(other.to_string()),
        }
    }
}

/// Strongly-typed row from `ai_radar.digests`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Digest {
    /// Primary key.
    pub id: Uuid,
    /// Digest cadence.
    pub digest_type: DigestType,
    /// Period start (inclusive).
    pub period_start: DateTime<Utc>,
    /// Period end (CHECK `>=` `period_start`).
    pub period_end: DateTime<Utc>,
    /// Markdown body.
    pub markdown_content: String,
    /// Free-form metadata.
    pub metadata_json: serde_json::Value,
    /// Row timestamp.
    pub generated_at: DateTime<Utc>,
}

/// Insert payload.
#[derive(Debug, Clone)]
pub struct NewDigest {
    /// Digest cadence.
    pub digest_type: DigestType,
    /// Period start (inclusive).
    pub period_start: DateTime<Utc>,
    /// Period end.
    pub period_end: DateTime<Utc>,
    /// Markdown body.
    pub markdown_content: String,
    /// Optional metadata.
    pub metadata_json: Option<serde_json::Value>,
}

impl NewDigest {
    /// Validate the payload.
    ///
    /// # Errors
    ///
    /// Returns when `period_end < period_start` or when
    /// `markdown_content` is blank.
    pub fn validate(&self) -> Result<(), String> {
        if self.period_end < self.period_start {
            return Err("period_end must be >= period_start".into());
        }
        if self.markdown_content.trim().is_empty() {
            return Err("markdown_content must not be empty".into());
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Duration;

    #[test]
    fn digest_type_roundtrip() {
        for v in [
            DigestType::Daily,
            DigestType::Weekly,
            DigestType::Monthly,
            DigestType::Custom,
        ] {
            assert_eq!(DigestType::parse(v.as_str()).unwrap(), v);
        }
    }

    #[test]
    fn digest_validation_catches_inverted_period() {
        let now = Utc::now();
        let d = NewDigest {
            digest_type: DigestType::Daily,
            period_start: now,
            period_end: now - Duration::hours(1),
            markdown_content: "x".into(),
            metadata_json: None,
        };
        assert!(d.validate().unwrap_err().contains("period_end"));
    }
}
