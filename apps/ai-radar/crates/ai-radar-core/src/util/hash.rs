//! Content hashing for collector idempotency.
//!
//! [`collector_content_hash`] implements the T-161 contract: SHA-256 hex of
//! `url || normalize(title) || normalize(body)` with stable whitespace
//! normalization. It is used as `NewRawItem::content_hash` so the same story
//! deduplicates even when the body is re-fetched with minor HTML changes.

use sha2::{Digest, Sha256};

/// Collapse all runs of Unicode whitespace to a single ASCII space and trim.
#[must_use]
pub fn normalize_whitespace(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// SHA-256 (hex) of the tuple `(url, normalized title, normalized body)`.
#[must_use]
pub fn collector_content_hash(url: &str, title: &str, raw_body: &str) -> String {
    let nu = normalize_whitespace(url.trim());
    let nt = normalize_whitespace(title);
    let nb = normalize_whitespace(raw_body);
    let mut hasher = Sha256::new();
    hasher.update(nu.as_bytes());
    hasher.update(b"\n");
    hasher.update(nt.as_bytes());
    hasher.update(b"\n");
    hasher.update(nb.as_bytes());
    format!("{:x}", hasher.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_collapses_space() {
        assert_eq!(normalize_whitespace("  hello   world\t\n "), "hello world");
    }

    #[test]
    fn collector_hash_stable_for_equivalent_whitespace() {
        let a = collector_content_hash("https://x/y", "  Title ", "foo   bar");
        let b = collector_content_hash("https://x/y", "Title", "foo bar");
        assert_eq!(a, b);
        assert_eq!(a.len(), 64);
    }
}
