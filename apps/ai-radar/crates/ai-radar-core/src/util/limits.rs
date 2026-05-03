//! Centralized size and concurrency caps for pipelines (**T-173**).
//!
//! Collectors and future extract/LLM stages should import limits from here
//! instead of scattering magic numbers.

/// Maximum `raw_items.raw_content` length we persist from RSS/HTML-like bodies.
///
/// Entries larger than this are **dropped** during collect (not truncated) so
/// memory and downstream extract stay bounded.
pub const MAX_RAW_CONTENT_BYTES: usize = 200_000;

/// Rough token budget reserved for extract prompts (T-165 uses the same number as a **char** cap).
pub const MAX_EXTRACT_INPUT_TOKENS: u32 = 8_000;

/// Maximum characters of `raw_content` embedded in the extractor user message (T-165).
pub const MAX_EXTRACT_INPUT_CHARS: usize = MAX_EXTRACT_INPUT_TOKENS as usize;

/// Global cap on concurrent LLM HTTP calls (not enforced until **T-164**/**T-165**).
pub const MAX_CONCURRENT_LLM_REQUESTS: u32 = 2;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn raw_content_cap_matches_t173() {
        assert_eq!(MAX_RAW_CONTENT_BYTES, 200_000);
        assert_eq!(MAX_EXTRACT_INPUT_TOKENS, 8_000);
        assert_eq!(MAX_EXTRACT_INPUT_CHARS, 8_000);
        assert_eq!(MAX_CONCURRENT_LLM_REQUESTS, 2);
    }
}
