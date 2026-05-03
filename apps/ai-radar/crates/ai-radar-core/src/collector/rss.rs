//! RSS / Atom collector using `feed-rs` + `reqwest`.

use std::io::Cursor;
use std::time::Duration;

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use feed_rs::model::Entry;
use feed_rs::parser;
use reqwest::StatusCode;
use uuid::Uuid;

use super::{CollectError, Collector};
use crate::domain::{NewRawItem, Source, SourceType};
use crate::metrics;
use crate::util::hash::collector_content_hash;
use crate::util::limits;
use crate::util::retry;

/// RSS/Atom pull collector.
#[derive(Debug, Clone)]
pub struct RssCollector {
    client: reqwest::Client,
    max_items: usize,
}

impl RssCollector {
    /// Build with the shared HTTP client configuration used by the pipeline.
    #[must_use]
    pub fn new(client: reqwest::Client, max_items: usize) -> Self {
        Self { client, max_items }
    }

    /// Factory for the AI Radar HTTP client (timeouts, redirects, User-Agent).
    ///
    /// # Errors
    ///
    /// Returns when the native TLS stack or provider configuration cannot
    /// build a client.
    pub fn default_http_client() -> reqwest::Result<reqwest::Client> {
        reqwest::Client::builder()
            .timeout(Duration::from_secs(15))
            .redirect(reqwest::redirect::Policy::limited(5))
            .user_agent(format!("ai-radar/{}", crate::VERSION))
            .build()
    }

    fn map_entry(
        source_id: Uuid,
        source_type: SourceType,
        source_feed_url: &str,
        entry: &Entry,
    ) -> Option<NewRawItem> {
        let url = first_entry_link(entry).unwrap_or_else(|| entry.id.clone());
        if url.trim().is_empty() {
            return None;
        }

        let title_str = entry
            .title
            .as_ref()
            .map(|t| t.content.trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_default();

        let mut raw_body = extract_body_html(entry);
        if raw_body.trim().is_empty() {
            raw_body.clone_from(&title_str);
        }
        if raw_body.trim().is_empty() {
            raw_body.clone_from(&url);
        }
        if raw_body.len() > limits::MAX_RAW_CONTENT_BYTES {
            tracing::warn!(
                source_id = %source_id,
                bytes = raw_body.len(),
                max = limits::MAX_RAW_CONTENT_BYTES,
                "rss entry rejected: raw body exceeds configured limit"
            );
            metrics::record_entry_rejected(source_type, "oversize_body");
            return None;
        }
        let raw_body = truncate_bytes(&raw_body, limits::MAX_RAW_CONTENT_BYTES);

        let published_at: Option<DateTime<Utc>> = entry.published.or(entry.updated);

        let hash = collector_content_hash(url.as_str(), title_str.as_str(), raw_body.as_str());

        let external_id = {
            let id = entry.id.trim();
            if id.is_empty() {
                None
            } else {
                Some(id.to_string())
            }
        };

        let metadata_json = serde_json::json!({
            "rss_entry_id": entry.id,
            "feed_url": source_feed_url,
        });

        Some(NewRawItem {
            source_id,
            external_id,
            url,
            title: if title_str.is_empty() {
                None
            } else {
                Some(title_str)
            },
            raw_content: raw_body,
            content_hash: Some(hash),
            metadata_json: Some(metadata_json),
            published_at,
        })
    }

    async fn fetch_feed_xml(&self, feed_url: &str) -> Result<Vec<u8>, CollectError> {
        /// Initial attempt plus retries for transient HTTP / transport failures.
        const MAX_ATTEMPTS: u32 = 4;
        let mut retry_after_hint: Option<std::time::Duration> = None;

        for attempt in 0..MAX_ATTEMPTS {
            if attempt > 0 {
                retry::sleep_before_http_retry(attempt - 1, retry_after_hint.take()).await;
            }

            let response = match self.client.get(feed_url).send().await {
                Ok(r) => r,
                Err(e) => {
                    if attempt + 1 < MAX_ATTEMPTS && retry::reqwest_send_error_is_retryable(&e) {
                        continue;
                    }
                    return Err(CollectError::from_reqwest(&e));
                }
            };

            let status = response.status();
            if retry::status_is_retryable(status) {
                retry_after_hint = if status == StatusCode::TOO_MANY_REQUESTS {
                    retry::parse_retry_after(response.headers())
                } else {
                    None
                };
                let _ = response.bytes().await;
                if attempt + 1 < MAX_ATTEMPTS {
                    continue;
                }
                return Err(CollectError::Fetch(format!(
                    "unexpected status {status} for {feed_url} (after retries)"
                )));
            }

            if !status.is_success() {
                let _ = response.bytes().await;
                return Err(CollectError::Fetch(format!(
                    "unexpected status {status} for {feed_url}"
                )));
            }

            return response
                .bytes()
                .await
                .map_err(|e| CollectError::from_reqwest(&e))
                .map(|b| b.to_vec());
        }

        Err(CollectError::Fetch(format!(
            "exhausted retries fetching {feed_url}"
        )))
    }
}

#[async_trait]
impl Collector for RssCollector {
    async fn collect(&self, source: &Source) -> Result<Vec<NewRawItem>, CollectError> {
        if source.source_type != SourceType::Rss {
            return Err(CollectError::Parse(format!(
                "source {} is {:?}, expected rss",
                source.id, source.source_type
            )));
        }

        let bytes = self.fetch_feed_xml(source.url.as_str()).await?;
        let parsed = parser::parse(Cursor::new(bytes))
            .map_err(|e| CollectError::Parse(format!("feed-rs: {e}")))?;

        let mut out = Vec::new();
        for entry in parsed.entries.iter().take(self.max_items) {
            if let Some(item) =
                Self::map_entry(source.id, source.source_type, source.url.as_str(), entry)
            {
                if item.validate().is_ok() {
                    out.push(item);
                }
            }
        }

        Ok(out)
    }
}

fn first_entry_link(entry: &Entry) -> Option<String> {
    entry
        .links
        .iter()
        .find(|l| l.rel.as_deref() == Some("alternate"))
        .map(|l| l.href.clone())
        .or_else(|| entry.links.first().map(|l| l.href.clone()))
}

fn extract_body_html(entry: &Entry) -> String {
    let from_content = entry
        .content
        .as_ref()
        .and_then(|c| c.body.as_deref())
        .map(str::to_string);
    let from_summary = entry.summary.as_ref().map(|s| s.content.clone());
    from_content.or(from_summary).unwrap_or_default()
}

fn truncate_bytes(s: &str, max: usize) -> String {
    if s.len() <= max {
        return s.to_string();
    }
    let mut end = max;
    while end > 0 && !s.is_char_boundary(end) {
        end -= 1;
    }
    s[..end].to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use wiremock::matchers::{method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    #[test]
    fn map_entry_builds_payload_from_fixture() {
        let xml = include_str!("../../tests/fixtures/rss/minimal.rss");
        let parsed = parser::parse(Cursor::new(xml.as_bytes())).expect("parse");
        let entry = &parsed.entries[0];
        let item = RssCollector::map_entry(
            Uuid::nil(),
            SourceType::Rss,
            "https://example.com/minimal.xml",
            entry,
        )
        .expect("mapped");
        assert_eq!(item.url, "https://example.com/posts/hello");
        assert_eq!(item.title.as_deref(), Some("Hello RSS"));
        assert!(item.raw_content.contains("Body"));
        assert!(item.content_hash.is_some());
    }

    #[tokio::test]
    async fn http_400_fails_fast_without_backoff_storm() {
        use std::time::Duration;

        let server = MockServer::start().await;
        Mock::given(method("GET"))
            .and(path("/bad.xml"))
            .respond_with(ResponseTemplate::new(400).set_body_string("no"))
            .mount(&server)
            .await;

        let client = RssCollector::default_http_client().expect("client");
        let collector = RssCollector::new(client, 50);
        let source = Source {
            id: Uuid::new_v4(),
            name: "bad".into(),
            source_type: SourceType::Rss,
            url: format!("{}/bad.xml", server.uri()),
            enabled: true,
            poll_interval_minutes: 30,
            last_polled_at: None,
            last_error: None,
            metadata_json: serde_json::json!({}),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };

        let started = std::time::Instant::now();
        let err = collector.collect(&source).await.expect_err("400");
        assert!(
            started.elapsed() < Duration::from_millis(800),
            "non-retryable status should not wait for backoff"
        );
        match err {
            CollectError::Fetch(msg) => assert!(msg.contains("400"), "{msg}"),
            e @ CollectError::Parse(_) => panic!("expected Fetch, got {e:?}"),
        }
    }

    #[tokio::test]
    async fn http_500_surfaces_after_retries() {
        use std::time::Duration;

        let server = MockServer::start().await;
        Mock::given(method("GET"))
            .and(path("/feed.xml"))
            .respond_with(ResponseTemplate::new(500).set_body_string("no"))
            .mount(&server)
            .await;

        let client = RssCollector::default_http_client().expect("client");
        let collector = RssCollector::new(client, 50);
        let source = Source {
            id: Uuid::new_v4(),
            name: "x".into(),
            source_type: SourceType::Rss,
            url: format!("{}/feed.xml", server.uri()),
            enabled: true,
            poll_interval_minutes: 30,
            last_polled_at: None,
            last_error: None,
            metadata_json: serde_json::json!({}),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };

        let started = std::time::Instant::now();
        let err = collector.collect(&source).await.expect_err("500");
        assert!(
            started.elapsed() < Duration::from_secs(12),
            "retries should finish within bounded time"
        );
        match err {
            CollectError::Fetch(msg) => assert!(
                msg.contains("500") && msg.contains("after retries"),
                "unexpected message: {msg}"
            ),
            e @ CollectError::Parse(_) => panic!("expected Fetch, got {e:?}"),
        }
    }

    #[tokio::test]
    async fn http_200_parses_entries() {
        let xml = include_str!("../../tests/fixtures/rss/minimal.rss");
        let server = MockServer::start().await;
        Mock::given(method("GET"))
            .and(path("/good.xml"))
            .respond_with(ResponseTemplate::new(200).set_body_string(xml))
            .mount(&server)
            .await;

        let client = RssCollector::default_http_client().expect("client");
        let collector = RssCollector::new(client, 50);
        let source = Source {
            id: Uuid::new_v4(),
            name: "good".into(),
            source_type: SourceType::Rss,
            url: format!("{}/good.xml", server.uri()),
            enabled: true,
            poll_interval_minutes: 30,
            last_polled_at: None,
            last_error: None,
            metadata_json: serde_json::json!({}),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };

        let items = collector.collect(&source).await.expect("collect");
        assert_eq!(items.len(), 1);
    }

    #[tokio::test]
    async fn http_200_oversize_entry_dropped() {
        use crate::util::limits;

        let big = "b".repeat(limits::MAX_RAW_CONTENT_BYTES + 50);
        let xml = format!(
            r#"<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>t</title>
<item><title>big</title><link>https://example.com/p1</link>
<description><![CDATA[{big}]]></description>
</item></channel></rss>"#
        );

        let server = MockServer::start().await;
        Mock::given(method("GET"))
            .and(path("/huge.xml"))
            .respond_with(ResponseTemplate::new(200).set_body_string(xml))
            .mount(&server)
            .await;

        let client = RssCollector::default_http_client().expect("client");
        let collector = RssCollector::new(client, 50);
        let source = Source {
            id: Uuid::new_v4(),
            name: "huge".into(),
            source_type: SourceType::Rss,
            url: format!("{}/huge.xml", server.uri()),
            enabled: true,
            poll_interval_minutes: 30,
            last_polled_at: None,
            last_error: None,
            metadata_json: serde_json::json!({}),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };

        let items = collector.collect(&source).await.expect("collect");
        assert!(
            items.is_empty(),
            "oversize description must not produce raw_items"
        );
    }
}
