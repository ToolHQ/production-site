//! Request-id middleware.
//!
//! Honors an inbound `X-Request-Id` header when present and well-formed (any
//! non-empty ASCII string up to 128 bytes), otherwise generates a fresh
//! `UUIDv4`. The id is stored as a request extension so handlers can access it
//! via [`axum::Extension`], and is echoed back on the response so external
//! callers can correlate logs.

use axum::extract::Request;
use axum::http::{HeaderName, HeaderValue};
use axum::middleware::Next;
use axum::response::Response;
use uuid::Uuid;

/// Header name used for inbound and outbound request correlation.
pub const REQUEST_ID_HEADER: &str = "x-request-id";

/// Maximum number of bytes accepted from inbound `X-Request-Id` headers.
const MAX_INBOUND_LEN: usize = 128;

/// Strongly-typed wrapper around the request id, stored as a request
/// extension so handlers can claim it via `Extension<RequestId>`.
#[derive(Debug, Clone)]
pub struct RequestId(pub String);

impl RequestId {
    /// Borrow the underlying string.
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Middleware that ensures every request carries a `RequestId` extension and
/// emits the corresponding response header.
pub async fn request_id_middleware(mut request: Request, next: Next) -> Response {
    let id = extract_or_generate(request.headers().get(REQUEST_ID_HEADER));
    let request_id = RequestId(id.clone());

    let span = tracing::info_span!("http.request", request_id = %id);
    let _enter = span.enter();

    request.extensions_mut().insert(request_id);

    let mut response = next.run(request).await;
    if let Ok(value) = HeaderValue::from_str(&id) {
        response
            .headers_mut()
            .insert(HeaderName::from_static(REQUEST_ID_HEADER), value);
    }
    response
}

fn extract_or_generate(header: Option<&HeaderValue>) -> String {
    if let Some(value) = header {
        if let Ok(text) = value.to_str() {
            let trimmed = text.trim();
            if !trimmed.is_empty() && trimmed.len() <= MAX_INBOUND_LEN && trimmed.is_ascii() {
                return trimmed.to_string();
            }
        }
    }
    Uuid::new_v4().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generates_uuid_when_header_missing() {
        let id = extract_or_generate(None);
        assert!(Uuid::parse_str(&id).is_ok(), "expected uuid, got {id}");
    }

    #[test]
    fn echoes_inbound_header_when_valid() {
        let header = HeaderValue::from_static("trace-abc-123");
        let id = extract_or_generate(Some(&header));
        assert_eq!(id, "trace-abc-123");
    }

    #[test]
    fn ignores_empty_header() {
        let header = HeaderValue::from_static("   ");
        let id = extract_or_generate(Some(&header));
        assert!(Uuid::parse_str(&id).is_ok());
    }

    #[test]
    fn ignores_oversized_header() {
        let big = "a".repeat(MAX_INBOUND_LEN + 1);
        let header = HeaderValue::from_str(&big).unwrap();
        let id = extract_or_generate(Some(&header));
        assert!(Uuid::parse_str(&id).is_ok());
    }
}
