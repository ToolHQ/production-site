//! GitHub releases and repository metadata collectors.

use async_trait::async_trait;
use serde_json::json;
use uuid::Uuid;

use super::client::{parse_github_timestamp, GitHubClient};
use crate::collector::{CollectError, Collector};
use crate::domain::{NewRawItem, Source, SourceType};
use crate::util::hash::collector_content_hash;
use crate::util::limits;

/// Collects `github_releases` and `github_repo` sources.
#[derive(Debug, Clone)]
pub struct GithubCollector {
    client: GitHubClient,
    max_items: usize,
}

impl GithubCollector {
    /// Wire the shared HTTP client and optional token.
    #[must_use]
    pub fn new(client: GitHubClient, max_items: usize) -> Self {
        Self { client, max_items }
    }

    fn map_release(
        source_id: Uuid,
        _source_type: SourceType,
        owner: &str,
        repo: &str,
        release: &serde_json::Value,
    ) -> Option<NewRawItem> {
        let id = release.get("id")?.as_i64()?;
        let html_url = release
            .get("html_url")
            .and_then(|v| v.as_str())
            .unwrap_or_else(|| {
                release
                    .get("url")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
            });
        if html_url.is_empty() {
            return None;
        }
        let tag = release
            .get("tag_name")
            .and_then(|v| v.as_str())
            .unwrap_or("release");
        let name = release
            .get("name")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .unwrap_or(tag);
        let body = release
            .get("body")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let raw_content = if body.trim().is_empty() {
            format!("{name}\n\n{html_url}")
        } else {
            body
        };
        if raw_content.len() > limits::MAX_RAW_CONTENT_BYTES {
            return None;
        }
        let published_at = release
            .get("published_at")
            .or_else(|| release.get("created_at"))
            .and_then(|v| v.as_str())
            .and_then(parse_github_timestamp);

        let hash = collector_content_hash(html_url, name, raw_content.as_str());
        Some(NewRawItem {
            source_id,
            external_id: Some(id.to_string()),
            url: html_url.to_string(),
            title: Some(name.to_string()),
            raw_content,
            content_hash: Some(hash),
            metadata_json: Some(json!({
                "github_owner": owner,
                "github_repo": repo,
                "tag_name": tag,
                "release_id": id,
            })),
            published_at,
        })
    }

    fn map_repo_meta(
        source_id: Uuid,
        owner: &str,
        repo: &str,
        data: &serde_json::Value,
    ) -> Option<NewRawItem> {
        let repo_id = data.get("id")?.as_i64()?;
        let full_name = data
            .get("full_name")
            .and_then(|v| v.as_str())
            .map(str::to_string)
            .unwrap_or_else(|| format!("{owner}/{repo}"));
        let html_url = data
            .get("html_url")
            .and_then(|v| v.as_str())
            .map(str::to_string)
            .unwrap_or_else(|| format!("https://github.com/{owner}/{repo}"));
        let raw_content = serde_json::to_string_pretty(data).ok()?;
        if raw_content.len() > limits::MAX_RAW_CONTENT_BYTES {
            return None;
        }
        let pushed_at = data
            .get("pushed_at")
            .and_then(|v| v.as_str())
            .and_then(parse_github_timestamp);
        let title = format!("{full_name} metadata");
        let hash = collector_content_hash(&html_url, title.as_str(), raw_content.as_str());
        Some(NewRawItem {
            source_id,
            external_id: Some(format!("repo:{repo_id}")),
            url: html_url,
            title: Some(title),
            raw_content,
            content_hash: Some(hash),
            metadata_json: Some(json!({
                "github_owner": owner,
                "github_repo": repo,
                "repo_id": repo_id,
                "stargazers_count": data.get("stargazers_count"),
                "forks_count": data.get("forks_count"),
                "open_issues_count": data.get("open_issues_count"),
                "license_spdx": data.get("license").and_then(|l| l.get("spdx_id")),
                "pushed_at": data.get("pushed_at"),
            })),
            published_at: pushed_at,
        })
    }
}

#[async_trait]
impl Collector for GithubCollector {
    async fn collect(&self, source: &Source) -> Result<Vec<NewRawItem>, CollectError> {
        let (owner, repo) = GitHubClient::parse_repo_url(source.url.as_str())?;
        match source.source_type {
            SourceType::GithubReleases => {
                let releases = self.client.list_releases(&owner, &repo).await?;
                let mut out = Vec::new();
                for release in releases.into_iter().take(self.max_items) {
                    if let Some(item) = Self::map_release(
                        source.id,
                        source.source_type,
                        &owner,
                        &repo,
                        &release,
                    ) {
                        if item.validate().is_ok() {
                            out.push(item);
                        }
                    }
                }
                Ok(out)
            }
            SourceType::GithubRepo => {
                let data = self.client.get_repo(&owner, &repo).await?;
                let item = Self::map_repo_meta(source.id, &owner, &repo, &data)
                    .ok_or_else(|| CollectError::Parse("empty github repo payload".into()))?;
                item.validate()
                    .map_err(|e| CollectError::Parse(e))?;
                Ok(vec![item])
            }
            other => Err(CollectError::Parse(format!(
                "source {} is {other:?}, expected github_releases or github_repo",
                source.id
            ))),
        }
    }
}
