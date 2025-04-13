use std::convert::Infallible;
use std::task::{Context, Poll};
use std::time::Instant;

use axum::body::Body;
use axum::http::{Request, Response, StatusCode};
use tower::{Layer, Service};
use uuid::Uuid;

use crate::context::{set_context_async, RequestContext};
use crate::logger::JsonLogger;

use serde_json::json; // ✅ Fixes json! macro not found

#[derive(Clone)]
pub struct RequestLoggerLayer {
    logger: JsonLogger,
}

impl RequestLoggerLayer {
    pub fn new(logger: JsonLogger) -> Self {
        Self { logger }
    }
}

impl<S> Layer<S> for RequestLoggerLayer {
    type Service = RequestLoggerMiddleware<S>;

    fn layer(&self, inner: S) -> Self::Service {
        RequestLoggerMiddleware {
            inner,
            logger: self.logger.clone(),
        }
    }
}

#[derive(Clone)]
pub struct RequestLoggerMiddleware<S> {
    inner: S,
    logger: JsonLogger,
}

impl<S> Service<Request<Body>> for RequestLoggerMiddleware<S>
where
    S: Service<Request<Body>, Response = Response<Body>, Error = Infallible> + Clone + Send + 'static,
    S::Future: Send + 'static,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self::Response, Self::Error>> + Send>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, req: Request<Body>) -> Self::Future {
        let logger = self.logger.clone();
        let method = req.method().clone();
        let path = req.uri().path().to_string();
        let req_id = Uuid::new_v4().to_string();
        let start_time = Instant::now();
        let mut inner = self.inner.clone();

        let headers = req.headers().clone();
        let user_agent = headers.get("user-agent")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("-")
            .to_string();

        let ip = headers
            .get("x-forwarded-for")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("::1")
            .to_string();

        let ctx = RequestContext::new(Some(req_id.clone()), None);

        Box::pin(set_context_async(ctx, move || async move {

            let result = inner.call(req).await;
            let duration = start_time.elapsed().as_secs_f64() * 1000.0;

            let status = result
                .as_ref()
                .map(|res| res.status())
                .unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);


            let message_obj = json!({
                "method": method.as_str(),
                "rawPath": path,
                "url": path,
                "statusCode": status.as_u16(),
                "responseTime": format!("{:.3}ms", duration),
                "bodyLength": 0,
                "userAgent": user_agent,
                "ipAddress": ip
            });

            logger.info(
                "Request received",
                Some(json!({
                    "req-id": req_id,
                    "event": "Request received",
                    "message": message_obj.to_string()
                }))
            );

            result
        }))
    }
}
