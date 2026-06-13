use axum::{
    http::header,
    response::{Html, IntoResponse, Response},
    routing::get,
    Router,
};

const TOKENS_CSS: &str = include_str!("../../ui/_static/tokens.css");
const APP_CSS: &str = include_str!("../../ui/_static/app.css");
const APP_JS: &str = include_str!("../../ui/_static/app.js");
const ICONS_SVG: &str = include_str!("../../ui/_static/icons.svg");
const FAVICON_SVG: &str = include_str!("../../ui/_static/favicon.svg");
const NOT_FOUND_HTML: &str = include_str!("../../ui/404.html");

fn css(body: &'static str) -> Response {
    ([(header::CONTENT_TYPE, "text/css; charset=utf-8"),
      (header::CACHE_CONTROL, "public, max-age=3600, stale-while-revalidate=86400")], body).into_response()
}
fn js(body: &'static str) -> Response {
    ([(header::CONTENT_TYPE, "application/javascript; charset=utf-8"),
      (header::CACHE_CONTROL, "public, max-age=3600, stale-while-revalidate=86400")], body).into_response()
}
fn svg(body: &'static str) -> Response {
    ([(header::CONTENT_TYPE, "image/svg+xml; charset=utf-8"),
      (header::CACHE_CONTROL, "public, max-age=86400, immutable")], body).into_response()
}

pub async fn not_found_page() -> (axum::http::StatusCode, Html<&'static str>) {
    (axum::http::StatusCode::NOT_FOUND, Html(NOT_FOUND_HTML))
}

pub fn router() -> Router<crate::app::AppState> {
    Router::new()
        .route("/_static/tokens.css", get(|| async { css(TOKENS_CSS) }))
        .route("/_static/app.css", get(|| async { css(APP_CSS) }))
        .route("/_static/app.js", get(|| async { js(APP_JS) }))
        .route("/_static/icons.svg", get(|| async { svg(ICONS_SVG) }))
        .route("/_static/favicon.svg", get(|| async { svg(FAVICON_SVG) }))
        .route("/favicon.svg", get(|| async { svg(FAVICON_SVG) }))
        .route("/favicon.ico", get(|| async { svg(FAVICON_SVG) }))
        .route("/robots.txt", get(robots_txt))
        .route("/sitemap.xml", get(sitemap_xml))
}

async fn robots_txt() -> Response {
    ([(header::CONTENT_TYPE, "text/plain; charset=utf-8"),
      (header::CACHE_CONTROL, "public, max-age=86400")],
     "User-agent: *\nAllow: /\n\nSitemap: https://agent-meter.dnor.io/sitemap.xml\n").into_response()
}

async fn sitemap_xml() -> Response {
    let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://agent-meter.dnor.io/</loc><changefreq>daily</changefreq><priority>1.0</priority></url>
  <url><loc>https://agent-meter.dnor.io/pricing</loc><changefreq>weekly</changefreq><priority>0.9</priority></url>
  <url><loc>https://agent-meter.dnor.io/quickstart</loc><changefreq>weekly</changefreq><priority>0.9</priority></url>
  <url><loc>https://agent-meter.dnor.io/vs</loc><changefreq>weekly</changefreq><priority>0.8</priority></url>
  <url><loc>https://agent-meter.dnor.io/vs/helicone</loc><changefreq>monthly</changefreq><priority>0.7</priority></url>
  <url><loc>https://agent-meter.dnor.io/vs/datadog</loc><changefreq>monthly</changefreq><priority>0.7</priority></url>
  <url><loc>https://agent-meter.dnor.io/vs/langsmith</loc><changefreq>monthly</changefreq><priority>0.7</priority></url>
  <url><loc>https://agent-meter.dnor.io/docs</loc><changefreq>weekly</changefreq><priority>0.8</priority></url>
  <url><loc>https://agent-meter.dnor.io/leaderboard</loc><changefreq>daily</changefreq><priority>0.7</priority></url>
  <url><loc>https://agent-meter.dnor.io/cost</loc><changefreq>daily</changefreq><priority>0.7</priority></url>
  <url><loc>https://agent-meter.dnor.io/conversations</loc><changefreq>daily</changefreq><priority>0.7</priority></url>
  <url><loc>https://agent-meter.dnor.io/status</loc><changefreq>daily</changefreq><priority>0.5</priority></url>
  <url><loc>https://agent-meter.dnor.io/login</loc><changefreq>monthly</changefreq><priority>0.4</priority></url>
</urlset>"#;
    ([(header::CONTENT_TYPE, "application/xml; charset=utf-8"),
      (header::CACHE_CONTROL, "public, max-age=86400")],
     xml).into_response()
}
