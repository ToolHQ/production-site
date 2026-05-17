//! HTML → plain text extraction (no JS rendering).

use scraper::{ElementRef, Html, Node, Selector};

/// Cleaned page text and title.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CleanContent {
    /// Document title (from `<title>` or first `<h1>`).
    pub title: String,
    /// Plain text with normalized whitespace.
    pub text: String,
}

/// Max cleaned text bytes kept in `raw_content`.
pub const MAX_CLEAN_TEXT_BYTES: usize = 50_000;

/// Strip scripts/styles and extract readable text from HTML.
///
/// # Errors
///
/// Returns when the HTML cannot be parsed.
pub fn extract(html: &str) -> Result<CleanContent, String> {
    let document = Html::parse_document(html);
    let title = document
        .select(&Selector::parse("title").expect("title selector"))
        .next()
        .map(|el| el.text().collect::<String>().trim().to_string())
        .filter(|t| !t.is_empty())
        .or_else(|| {
            document
                .select(&Selector::parse("h1").expect("h1 selector"))
                .next()
                .map(|el| el.text().collect::<String>().trim().to_string())
        })
        .unwrap_or_else(|| "Untitled".to_string());

    let body_sel = Selector::parse("body").map_err(|e| e.to_string())?;
    let html_sel = Selector::parse("html").map_err(|e| e.to_string())?;
    let root = document
        .select(&body_sel)
        .next()
        .or_else(|| document.select(&html_sel).next());
    let raw_text = root.map(text_without_script_style).unwrap_or_default();
    let text = normalize_whitespace(&raw_text);
    let text = truncate_with_notice(&text, MAX_CLEAN_TEXT_BYTES);
    Ok(CleanContent { title, text })
}

fn text_without_script_style(element: ElementRef<'_>) -> String {
    let mut out = String::new();
    for child in element.children() {
        match child.value() {
            Node::Text(t) => out.push_str(&t.text),
            Node::Element(el) if !matches!(el.name(), "script" | "style") => {
                if let Some(child_el) = ElementRef::wrap(child) {
                    let chunk = text_without_script_style(child_el);
                    if !chunk.is_empty() {
                        if !out.is_empty() && !out.ends_with('\n') {
                            out.push('\n');
                        }
                        out.push_str(&chunk);
                    }
                }
            }
            _ => {}
        }
    }
    out
}

fn normalize_whitespace(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut prev_blank = false;
    for line in s.lines() {
        let line = line.split_whitespace().collect::<Vec<_>>().join(" ");
        if line.is_empty() {
            if !prev_blank && !out.is_empty() {
                out.push('\n');
                prev_blank = true;
            }
            continue;
        }
        if !out.is_empty() && !prev_blank {
            out.push('\n');
        }
        out.push_str(&line);
        prev_blank = false;
    }
    out.trim().to_string()
}

fn truncate_with_notice(s: &str, max: usize) -> String {
    if s.len() <= max {
        return s.to_string();
    }
    let mut end = max.saturating_sub(64);
    while end > 0 && !s.is_char_boundary(end) {
        end -= 1;
    }
    format!(
        "{}\n\n[truncated at {max} bytes]",
        &s[..end],
        max = max
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_script_and_style() {
        let html = include_str!("../../../tests/fixtures/web/with_script.html");
        let clean = extract(html).expect("extract");
        assert!(!clean.text.to_lowercase().contains("alert"));
        assert!(clean.text.contains("Visible paragraph"));
        assert_eq!(clean.title, "Script page");
    }
}
