//! HTTP fetch with size limits for manual webpage sources.

use std::time::Duration;

use crate::collector::CollectError;
use crate::util::retry::{self, RetryDirective, RetryPolicy};

/// Maximum downloaded HTML bytes (pre-decode).
pub const MAX_FETCH_BYTES: usize = 1_024 * 1_024;

/// Fetch configuration for [`WebFetcher`].
#[derive(Debug, Clone)]
pub struct WebFetcherConfig {
    /// Total request timeout.
    pub timeout: Duration,
    /// Maximum response body bytes.
    pub max_bytes: usize,
}

impl Default for WebFetcherConfig {
    fn default() -> Self {
        Self {
            timeout: Duration::from_secs(20),
            max_bytes: MAX_FETCH_BYTES,
        }
    }
}

/// Bounded HTTP fetcher for arbitrary URLs.
#[derive(Debug, Clone)]
pub struct WebFetcher {
    client: reqwest::Client,
    config: WebFetcherConfig,
}

impl WebFetcher {
    /// Build with explicit configuration.
    #[must_use]
    pub fn new(client: reqwest::Client, config: WebFetcherConfig) -> Self {
        Self { client, config }
    }

    /// Default client: 20s timeout, 5 redirects, AI Radar user agent.
    ///
    /// # Errors
    ///
    /// Returns when TLS/client construction fails.
    pub fn default_http_client() -> reqwest::Result<reqwest::Client> {
        reqwest::Client::builder()
            .timeout(Duration::from_secs(20))
            .redirect(reqwest::redirect::Policy::limited(5))
            .user_agent(format!("ai-radar/{}", crate::VERSION))
            .build()
    }

    /// Download HTML up to [`WebFetcherConfig::max_bytes`].
    ///
    /// # Errors
    ///
    /// Returns [`CollectError::Fetch`] on HTTP/network failures or oversize bodies.
    pub async fn fetch(&self, url: &str) -> Result<String, CollectError> {
        let policy = RetryPolicy::http_default();
        let client = self.client.clone();
        let max_bytes = self.config.max_bytes;
        let url = url.to_string();

        let bytes = retry::with_retry(
            policy,
            || {
                let client = client.clone();
                let url = url.clone();
                async move {
                    let response = client
                        .get(&url)
                        .send()
                        .await
                        .map_err(|e| CollectError::from_reqwest(&e))?;

                    let status = response.status();
                    if !status.is_success() {
                        return Err(CollectError::Fetch(format!(
                            "unexpected status {status} for {url}"
                        )));
                    }

                    if let Some(len) = response.content_length() {
                        if len > max_bytes as u64 {
                            return Err(CollectError::Fetch(format!(
                                "content-length {len} exceeds max {max_bytes} for {url}"
                            )));
                        }
                    }

                    let mut buf = Vec::new();
                    let mut stream = response.bytes_stream();
                    use futures::StreamExt;
                    while let Some(chunk) = stream.next().await {
                        let chunk = chunk.map_err(|e| CollectError::from_reqwest(&e))?;
                        if buf.len() + chunk.len() > max_bytes {
                            return Err(CollectError::Fetch(format!(
                                "response exceeds {max_bytes} bytes for {url}"
                            )));
                        }
                        buf.extend_from_slice(&chunk);
                    }
                    Ok(buf)
                }
            },
            |_attempt, err| match err {
                CollectError::Fetch(msg)
                    if msg.contains("502") || msg.contains("503") || msg.contains("504") =>
                {
                    RetryDirective::Again { retry_after: None }
                }
                _ => RetryDirective::Abort,
            },
        )
        .await?;

        String::from_utf8(bytes).map_err(|e| {
            CollectError::Parse(format!("page is not valid utf-8: {e}"))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wiremock::matchers::{method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    #[tokio::test]
    async fn rejects_content_length_over_limit() {
        let server = MockServer::start().await;
        Mock::given(method("GET"))
            .and(path("/big"))
            .respond_with(ResponseTemplate::new(200).set_body_string("x".repeat(2_000_000)))
            .mount(&server)
            .await;

        let client = WebFetcher::default_http_client().expect("client");
        let fetcher = WebFetcher::new(client, WebFetcherConfig::default());
        let err = fetcher
            .fetch(&format!("{}/big", server.uri()))
            .await
            .expect_err("oversize");
        match err {
            CollectError::Fetch(msg) => assert!(msg.contains("content-length"), "{msg}"),
            e => panic!("expected Fetch, got {e:?}"),
        }
    }
}
