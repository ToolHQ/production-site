//! HTTP-oriented backoff with jitter (T-173 slice).
//!
//! Used by collectors for transient `reqwest` failures and retryable status
//! codes. Jitter is ±20% around the exponential step to reduce thundering herd.

use std::time::Duration;

use reqwest::header::HeaderMap;
use reqwest::StatusCode;

const BASE_MS: u64 = 250;
const CAP_MS: u64 = 20_000;

/// Parse `Retry-After` as a delay in seconds (RFC 7231 integer form only).
///
/// Caps at **120s** so a misbehaving server cannot stall the collector for long.
#[must_use]
pub fn parse_retry_after(headers: &HeaderMap) -> Option<Duration> {
    let raw = headers.get(reqwest::header::RETRY_AFTER)?.to_str().ok()?;
    let secs: u64 = raw.parse().ok()?;
    Some(Duration::from_secs(secs.min(120)))
}

/// Whether an HTTP status should trigger another fetch attempt.
#[must_use]
pub fn status_is_retryable(status: StatusCode) -> bool {
    matches!(
        status,
        StatusCode::REQUEST_TIMEOUT
            | StatusCode::TOO_MANY_REQUESTS
            | StatusCode::BAD_GATEWAY
            | StatusCode::SERVICE_UNAVAILABLE
            | StatusCode::GATEWAY_TIMEOUT
    ) || (status.is_server_error() && status != StatusCode::NOT_IMPLEMENTED)
}

/// Whether a [`reqwest::Error`] from [`reqwest::Client::send`] is worth retrying.
#[must_use]
pub fn reqwest_send_error_is_retryable(err: &reqwest::Error) -> bool {
    if err.is_timeout() || err.is_connect() {
        return true;
    }
    err.status().is_some_and(status_is_retryable)
}

/// Exponential backoff with ±20% jitter, capped at [`CAP_MS`].
#[must_use]
pub fn jittered_backoff_ms(attempt: u32) -> u64 {
    let mult = 2u32.pow(attempt.min(6));
    let raw = BASE_MS.saturating_mul(u64::from(mult)).min(CAP_MS);
    let lo = raw.saturating_mul(8).saturating_div(10).max(1);
    let hi = raw.saturating_mul(12).saturating_div(10).max(lo);
    fastrand::u64(lo..=hi)
}

/// Sleep before HTTP retry `attempt` (0-based after the first failure).
pub async fn sleep_before_http_retry(attempt: u32, retry_after: Option<Duration>) {
    let mut delay = Duration::from_millis(jittered_backoff_ms(attempt));
    if let Some(ra) = retry_after {
        delay = delay.max(ra);
    }
    tokio::time::sleep(delay).await;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn jittered_backoff_stays_within_twenty_percent_band() {
        for attempt in 0..4u32 {
            let mult = 2u32.pow(attempt.min(6));
            let raw = BASE_MS.saturating_mul(u64::from(mult)).min(CAP_MS);
            let lo = raw.saturating_mul(8).saturating_div(10).max(1);
            let hi = raw.saturating_mul(12).saturating_div(10).max(lo);
            for _ in 0..30 {
                let j = jittered_backoff_ms(attempt);
                assert!(
                    (lo..=hi).contains(&j),
                    "attempt {attempt}: {j} not in {lo}..={hi}"
                );
            }
        }
    }

    #[test]
    fn parse_retry_after_caps() {
        let mut headers = HeaderMap::new();
        headers.insert(reqwest::header::RETRY_AFTER, "3".parse().unwrap());
        assert_eq!(parse_retry_after(&headers), Some(Duration::from_secs(3)));

        let mut headers = HeaderMap::new();
        headers.insert(reqwest::header::RETRY_AFTER, "9999".parse().unwrap());
        assert_eq!(parse_retry_after(&headers), Some(Duration::from_secs(120)));
    }
}
