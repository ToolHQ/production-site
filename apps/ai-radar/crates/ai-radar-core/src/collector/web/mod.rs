//! Manual webpage collector (`source_type = webpage`).

mod cleaner;
mod fetcher;

pub use cleaner::{extract, CleanContent, MAX_CLEAN_TEXT_BYTES};
pub use fetcher::{WebFetcher, WebFetcherConfig, MAX_FETCH_BYTES};

use async_trait::async_trait;
use serde_json::json;

use crate::collector::{CollectError, Collector};
use crate::domain::{NewRawItem, Source, SourceType};
use crate::util::hash::collector_content_hash;
use crate::util::limits;

/// Fetches and cleans a single configured URL per source.
#[derive(Debug, Clone)]
pub struct WebCollector {
    fetcher: WebFetcher,
}

impl WebCollector {
    /// Build from an existing [`WebFetcher`].
    #[must_use]
    pub fn new(fetcher: WebFetcher) -> Self {
        Self { fetcher }
    }
}

#[async_trait]
impl Collector for WebCollector {
    async fn collect(&self, source: &Source) -> Result<Vec<NewRawItem>, CollectError> {
        if source.source_type != SourceType::Webpage {
            return Err(CollectError::Parse(format!(
                "source {} is {:?}, expected webpage",
                source.id, source.source_type
            )));
        }
        let html = self.fetcher.fetch(source.url.as_str()).await?;
        let clean = extract(&html).map_err(CollectError::Parse)?;
        if clean.text.is_empty() {
            return Err(CollectError::Parse("page has no extractable text".into()));
        }
        let raw_content = if clean.text.len() > limits::MAX_RAW_CONTENT_BYTES {
            clean.text[..limits::MAX_RAW_CONTENT_BYTES].to_string()
        } else {
            clean.text.clone()
        };
        let hash = collector_content_hash(
            source.url.as_str(),
            clean.title.as_str(),
            raw_content.as_str(),
        );
        let item = NewRawItem {
            source_id: source.id,
            external_id: None,
            url: source.url.clone(),
            title: Some(clean.title),
            raw_content,
            content_hash: Some(hash),
            metadata_json: Some(json!({
                "fetch_url": source.url,
                "clean_bytes": clean.text.len(),
            })),
            published_at: None,
        };
        item.validate()
            .map_err(CollectError::Parse)?;
        Ok(vec![item])
    }
}
