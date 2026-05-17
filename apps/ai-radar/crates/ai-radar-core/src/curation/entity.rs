//! Canonical entity keys for cross-source deduplication (**T-231**).

use serde_json::Value;
use strsim::jaro_winkler;

use crate::domain::NewRawItem;

/// Similarity threshold for tool names on the same registrable domain.
const NAME_SIMILARITY_THRESHOLD: f64 = 0.92;

/// Resolved identity for a raw item prior to extract.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EntityIdentity {
    /// Stable key (`github:owner/repo`, `domain:slug`, …).
    pub tool_key: String,
    /// Normalized URL for operators (GitHub repo URL when applicable).
    pub canonical_url: String,
}

/// Derive entity identity from a newly collected raw row.
#[must_use]
pub fn tool_key_from_new_raw_item(item: &NewRawItem) -> Option<EntityIdentity> {
    if let Some(id) = tool_key_from_github_metadata(item.metadata_json.as_ref()) {
        return Some(id);
    }
    if let Some(id) = tool_key_from_url(&item.url) {
        return Some(id);
    }
    tool_key_from_title_and_url(item.title.as_deref(), &item.url)
}

/// Build key from `metadata_json.github_owner` / `github_repo`.
#[must_use]
pub fn tool_key_from_github_metadata(meta: Option<&Value>) -> Option<EntityIdentity> {
    let obj = meta?.as_object()?;
    let owner = obj.get("github_owner")?.as_str()?.trim();
    let repo = obj
        .get("github_repo")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty())?;
    if owner.is_empty() || repo.is_empty() {
        return None;
    }
    let owner_l = owner.to_ascii_lowercase();
    let repo_l = repo.to_ascii_lowercase();
    Some(EntityIdentity {
        tool_key: format!("github:{owner_l}/{repo_l}"),
        canonical_url: format!("https://github.com/{owner_l}/{repo_l}"),
    })
}

/// Parse `https://github.com/owner/repo(/…)?` into a stable key.
#[must_use]
pub fn tool_key_from_url(url: &str) -> Option<EntityIdentity> {
    let normalized = normalize_url(url)?;
    let path = normalized.strip_prefix("https://github.com/")?;
    let mut parts = path.split('/').filter(|p| !p.is_empty());
    let owner = parts.next()?;
    let repo = parts.next()?;
    if owner.eq_ignore_ascii_case("releases")
        || owner.eq_ignore_ascii_case("topics")
        || repo.contains('.')
    {
        return None;
    }
    let owner_l = owner.to_ascii_lowercase();
    let repo_l = repo.to_ascii_lowercase();
    Some(EntityIdentity {
        tool_key: format!("github:{owner_l}/{repo_l}"),
        canonical_url: format!("https://github.com/{owner_l}/{repo_l}"),
    })
}

/// Weak key: same registrable domain + similar normalized title.
#[must_use]
pub fn tool_key_from_title_and_url(title: Option<&str>, url: &str) -> Option<EntityIdentity> {
    let title = normalize_tool_name(title?);
    if title.len() < 3 {
        return None;
    }
    let domain = registrable_domain(url)?;
    let slug = slugify(&title);
    if slug.len() < 3 {
        return None;
    }
    Some(EntityIdentity {
        tool_key: format!("domain:{domain}:{slug}"),
        canonical_url: normalize_url(url).unwrap_or_else(|| url.to_string()),
    })
}

/// Normalize URL for comparison (lowercase host, no fragment/query, trim trailing slash).
#[must_use]
pub fn normalize_url(url: &str) -> Option<String> {
    let trimmed = url.trim();
    if trimmed.is_empty() {
        return None;
    }
    let lower = trimmed.to_ascii_lowercase();
    let without_fragment = lower.split('#').next().unwrap_or(&lower);
    let mut base = without_fragment.split('?').next().unwrap_or(without_fragment).to_string();
    while base.ends_with('/') && base.len() > "https://x.com".len() {
        base.pop();
    }
    if base.starts_with("http://") || base.starts_with("https://") {
        Some(base)
    } else {
        None
    }
}

/// Normalize a product name for fuzzy comparison.
#[must_use]
pub fn normalize_tool_name(name: &str) -> String {
    let mut s = name.trim().to_ascii_lowercase();
    for suffix in [" inc.", " inc", " llc", " ltd", " gmbh", "-ai", " ai"] {
        if let Some(stripped) = s.strip_suffix(suffix) {
            s = stripped.to_string();
        }
    }
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Returns true when two names are similar enough to treat as one entity on the same domain.
#[must_use]
pub fn names_similar(a: &str, b: &str) -> bool {
    let na = normalize_tool_name(a);
    let nb = normalize_tool_name(b);
    if na.is_empty() || nb.is_empty() {
        return false;
    }
    if na == nb {
        return true;
    }
    jaro_winkler(&na, &nb) >= NAME_SIMILARITY_THRESHOLD
}

fn slugify(s: &str) -> String {
    let mut out = String::new();
    let mut prev_hyphen = false;
    for c in normalize_tool_name(s).chars() {
        if c.is_ascii_alphanumeric() {
            out.push(c);
            prev_hyphen = false;
        } else if !prev_hyphen {
            out.push('-');
            prev_hyphen = true;
        }
    }
    out.trim_matches('-').to_string()
}

fn registrable_domain(url: &str) -> Option<String> {
    let normalized = normalize_url(url)?;
    let rest = normalized
        .strip_prefix("https://")
        .or_else(|| normalized.strip_prefix("http://"))?;
    let host = rest.split('/').next()?;
    if host == "github.com" {
        return None;
    }
    let parts: Vec<&str> = host.split('.').collect();
    if parts.len() >= 2 {
        Some(format!("{}.{}", parts[parts.len() - 2], parts[parts.len() - 1]))
    } else {
        Some(host.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn github_url_normalizes() {
        let id = tool_key_from_url("https://github.com/Ollama/Ollama/releases/tag/v1").unwrap();
        assert_eq!(id.tool_key, "github:ollama/ollama");
        assert_eq!(id.canonical_url, "https://github.com/ollama/ollama");
    }

    #[test]
    fn github_metadata_key() {
        let item = NewRawItem {
            source_id: uuid::Uuid::nil(),
            external_id: None,
            url: "https://github.com/foo/bar".into(),
            title: None,
            raw_content: "x".into(),
            content_hash: None,
            metadata_json: Some(json!({"github_owner": "Foo", "github_repo": "Bar"})),
            published_at: None,
        };
        let id = tool_key_from_new_raw_item(&item).unwrap();
        assert_eq!(id.tool_key, "github:foo/bar");
    }

    #[test]
    fn names_similar_for_typos() {
        assert!(names_similar("Ollama", "ollama"));
        assert!(names_similar("Langfuse", "LangFuse"));
    }

    #[test]
    fn different_products_not_similar() {
        assert!(!names_similar("Ollama", "Kubernetes"));
    }
}
