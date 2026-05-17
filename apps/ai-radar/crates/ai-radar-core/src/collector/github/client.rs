//! GitHub REST API client with rate-limit awareness.

use std::time::Duration;

use chrono::{DateTime, Utc};
use reqwest::header::{HeaderMap, ACCEPT, AUTHORIZATION, USER_AGENT};
use reqwest::StatusCode;
use serde_json::Value;

use crate::collector::CollectError;
use crate::util::retry::{self, RetryDirective, RetryPolicy};

const DEFAULT_API_BASE: &str = "https://api.github.com";
const MAX_RATE_LIMIT_WAIT_SECS: u64 = 90;
const MAX_LINK_PAGES: u32 = 3;

/// Low-level GitHub HTTP client.
#[derive(Debug, Clone)]
pub struct GitHubClient {
    http: reqwest::Client,
    token: Option<String>,
    api_base: String,
}

impl GitHubClient {
    /// Build a client with optional `GITHUB_TOKEN` for higher rate limits.
    #[must_use]
    pub fn new(http: reqwest::Client, token: Option<String>) -> Self {
        Self {
            http,
            token,
            api_base: DEFAULT_API_BASE.to_string(),
        }
    }

    /// Override API base URL (wiremock tests).
    #[must_use]
    pub fn with_api_base(mut self, api_base: impl Into<String>) -> Self {
        self.api_base = api_base.into();
        self
    }

    fn default_headers(&self) -> HeaderMap {
        let mut headers = HeaderMap::new();
        headers.insert(
            USER_AGENT,
            format!("ai-radar/{}", crate::VERSION).parse().expect("ua"),
        );
        headers.insert(
            ACCEPT,
            "application/vnd.github+json".parse().expect("accept"),
        );
        if let Some(token) = &self.token {
            if let Ok(v) = format!("Bearer {token}").parse() {
                headers.insert(AUTHORIZATION, v);
            }
        }
        headers
    }

    /// Parse `https://github.com/{owner}/{repo}` (optional `.git`, trailing slash).
    ///
    /// # Errors
    ///
    /// Returns [`CollectError::Parse`] when the URL is not a GitHub repo path.
    pub fn parse_repo_url(url: &str) -> Result<(String, String), CollectError> {
        let trimmed = url.trim().trim_end_matches('/');
        let path = trimmed
            .strip_prefix("https://github.com/")
            .or_else(|| trimmed.strip_prefix("http://github.com/"))
            .ok_or_else(|| {
                CollectError::Parse(format!("not a github.com repo URL: {url}"))
            })?;
        let path = path.strip_suffix(".git").unwrap_or(path);
        let mut parts = path.split('/').filter(|s| !s.is_empty());
        let owner = parts
            .next()
            .ok_or_else(|| CollectError::Parse(format!("missing owner in {url}")))?
            .to_string();
        let repo = parts
            .next()
            .ok_or_else(|| CollectError::Parse(format!("missing repo in {url}")))?
            .to_string();
        if parts.next().is_some() {
            return Err(CollectError::Parse(format!(
                "expected owner/repo, got extra path segments in {url}"
            )));
        }
        Ok((owner, repo))
    }

    /// Repository metadata (`GET /repos/{owner}/{repo}`).
    ///
    /// # Errors
    ///
    /// Propagates HTTP, rate-limit, and JSON errors.
    pub async fn get_repo(&self, owner: &str, repo: &str) -> Result<Value, CollectError> {
        let url = format!("{}/repos/{owner}/{repo}", self.api_base);
        self.get_json(&url).await
    }

    /// Release list, following `Link` pagination up to [`MAX_LINK_PAGES`].
    ///
    /// # Errors
    ///
    /// Propagates HTTP, rate-limit, and JSON errors.
    pub async fn list_releases(&self, owner: &str, repo: &str) -> Result<Vec<Value>, CollectError> {
        let mut url = format!("{}/repos/{owner}/{repo}/releases?per_page=30", self.api_base);
        let mut all = Vec::new();
        for page in 0..MAX_LINK_PAGES {
            let (items, next) = self.get_json_array_page(&url).await?;
            all.extend(items);
            match next {
                Some(next_url) if page + 1 < MAX_LINK_PAGES => url = next_url,
                _ => break,
            }
        }
        Ok(all)
    }

    /// README body (`GET /repos/{owner}/{repo}/readme`).
    ///
    /// # Errors
    ///
    /// Propagates HTTP, rate-limit, and JSON errors.
    pub async fn get_readme(&self, owner: &str, repo: &str) -> Result<Value, CollectError> {
        let url = format!("{}/repos/{owner}/{repo}/readme", self.api_base);
        self.get_json(&url).await
    }

    async fn get_json(&self, url: &str) -> Result<Value, CollectError> {
        self.get_json_array_page(url)
            .await
            .map(|(v, _)| v.into_iter().next().unwrap_or(Value::Null))
    }

    async fn get_json_array_page(
        &self,
        url: &str,
    ) -> Result<(Vec<Value>, Option<String>), CollectError> {
        self.get_json_array_page_inner(url, false).await
    }

    async fn get_json_array_page_inner(
        &self,
        url: &str,
        rate_limit_retried: bool,
    ) -> Result<(Vec<Value>, Option<String>), CollectError> {
        let policy = RetryPolicy::http_default();
        let http = self.http.clone();
        let headers = self.default_headers();
        let url_owned = url.to_string();

        let response = retry::with_retry(
            policy,
            || {
                let http = http.clone();
                let headers = headers.clone();
                let url = url_owned.clone();
                async move {
                    http.get(&url)
                        .headers(headers)
                        .send()
                        .await
                        .map_err(|e| CollectError::from_reqwest(&e))
                }
            },
            |_attempt, err| classify_github_retry(err),
        )
        .await?;

        if !rate_limit_retried {
            if let Some(wait) = rate_limit_wait_from_headers(response.headers()) {
                if wait > Duration::ZERO {
                    tracing::warn!(
                        wait_secs = wait.as_secs(),
                        url,
                        "github rate limit exhausted, waiting"
                    );
                    tokio::time::sleep(wait).await;
                    return Box::pin(self.get_json_array_page_inner(url, true)).await;
                }
            }
        }

        let status = response.status();
        let link = response
            .headers()
            .get("link")
            .and_then(|v| v.to_str().ok())
            .map(str::to_string);
        let body = response
            .bytes()
            .await
            .map_err(|e| CollectError::from_reqwest(&e))?;

        if status == StatusCode::FORBIDDEN && body.starts_with(b"{\"message\":\"API rate limit") {
            return Err(CollectError::RateLimited(
                "GitHub API rate limit (403)".into(),
            ));
        }

        if status == StatusCode::UNAUTHORIZED {
            return Err(CollectError::Fetch(format!(
                "GitHub unauthorized for {url} (check GITHUB_TOKEN)"
            )));
        }

        if !status.is_success() {
            return Err(CollectError::Fetch(format!(
                "GitHub HTTP {status} for {url}: {}",
                String::from_utf8_lossy(&body[..body.len().min(200)])
            )));
        }

        let next = link.as_deref().and_then(parse_link_next);
        if body.first() == Some(&b'[') {
            let items: Vec<Value> = serde_json::from_slice(&body)
                .map_err(|e| CollectError::Parse(format!("github json array: {e}")))?;
            return Ok((items, next));
        }

        let value: Value = serde_json::from_slice(&body)
            .map_err(|e| CollectError::Parse(format!("github json: {e}")))?;
        Ok((vec![value], next))
    }
}

fn classify_github_retry(err: &CollectError) -> RetryDirective {
    match err {
        CollectError::Fetch(msg) if msg.contains("429") || msg.contains("502") => {
            RetryDirective::Again { retry_after: None }
        }
        CollectError::RateLimited(_) => RetryDirective::Again { retry_after: None },
        _ => RetryDirective::Abort,
    }
}

/// Seconds to sleep when `x-ratelimit-remaining` is 0 (capped at 90s).
#[must_use]
pub fn rate_limit_wait_from_headers(headers: &HeaderMap) -> Option<Duration> {
    let remaining = headers
        .get("x-ratelimit-remaining")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.parse::<i64>().ok())?;
    if remaining > 0 {
        return None;
    }
    let reset = headers
        .get("x-ratelimit-reset")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.parse::<i64>().ok())?;
    let now = Utc::now().timestamp();
    let wait = (reset - now).max(0).min(i64::try_from(MAX_RATE_LIMIT_WAIT_SECS).unwrap_or(90));
    Some(Duration::from_secs(wait as u64))
}

/// Parse RFC 5988 `Link` header for `rel="next"`.
#[must_use]
pub fn parse_link_next(link: &str) -> Option<String> {
    for part in link.split(',') {
        let part = part.trim();
        if part.contains("rel=\"next\"") || part.contains("rel='next'") {
            let start = part.find('<')? + 1;
            let end = part.find('>')?;
            return Some(part[start..end].to_string());
        }
    }
    None
}

/// Parse GitHub `published_at` / `created_at` timestamps.
#[must_use]
pub fn parse_github_timestamp(s: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|dt| dt.with_timezone(&Utc))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_repo_url_accepts_common_forms() {
        let (o, r) =
            GitHubClient::parse_repo_url("https://github.com/rust-lang/rust").expect("parse");
        assert_eq!(o, "rust-lang");
        assert_eq!(r, "rust");
        let (o, r) =
            GitHubClient::parse_repo_url("https://github.com/owner/repo.git/").expect("parse");
        assert_eq!(o, "owner");
        assert_eq!(r, "repo");
    }

    #[test]
    fn parse_link_next_extracts_url() {
        let link = r#"<https://api.github.com/repos/x/y/releases?page=2>; rel="next", <https://api.github.com/repos/x/y/releases?page=1>; rel="first""#;
        assert_eq!(
            parse_link_next(link).as_deref(),
            Some("https://api.github.com/repos/x/y/releases?page=2")
        );
    }
}
